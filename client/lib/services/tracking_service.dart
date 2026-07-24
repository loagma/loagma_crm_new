import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';

import 'api_service.dart';
import 'user_service.dart';

/// Continuous GPS capture while punched in.
///
/// Runs a foreground service (persistent notification, NO background-location
/// permission) whose background isolate:
///  - captures positions on a ~5m distance filter plus an accuracy gate,
///  - queues them in a local sqflite table with capture-time timestamps,
///  - flushes batches to /api/tracking/ping every ~9s,
///  - keeps the queue on failure, clears it on success.
///
/// start() is called after punch-in success, stop() after punch-out success
/// (see app_drawer.dart). Both no-op when already in the desired state.
class TrackingService {
  TrackingService._();

  // Upload cadence for the queued pings. Kept just under the 10s capture
  // interval so a fresh fix reaches the server within ~1 cycle of being
  // recorded — this is what lets the admin's live map reflect movement
  // promptly (a turn shows in ~10-15s instead of up to ~45s). Cheap: _flush()
  // makes NO network call when the queue is empty, so a short interval doesn't
  // multiply data/battery — it only shortens how long a real point waits.
  static const int _flushIntervalMs = 9000;

  static Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) return;

    // Android 13+ needs runtime notification permission for the
    // foreground-service notification to be visible.
    try {
      final status = await FlutterForegroundTask.checkNotificationPermission();
      if (status != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } catch (_) {}

    // Without a battery-optimization exemption, Android 14+ suppresses fused
    // location delivery once the screen turns off — verified on device A069
    // (2 points in a 23-min screen-off walk vs 140 with the screen on).
    try {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (_) {}

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'loagma_tracking',
        channelName: 'Route Tracking',
        channelDescription: 'Shown while your on-duty route is being recorded',
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(_flushIntervalMs), // flush ~9s
        allowWakeLock: true,
      ),
    );

    await FlutterForegroundTask.startService(
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: 'LoagmaCRM — On Duty',
      notificationText: 'Recording your route while punched in',
      callback: trackingTaskCallback,
    );
  }

  static Future<void> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }
}

@pragma('vm:entry-point')
void trackingTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_TrackingTaskHandler());
}

class _TrackingTaskHandler extends TaskHandler {
  // Android suppresses displacement-only fused listeners once the screen is
  // off (verified on A069: 2 points per 23-min screen-off walk). So we ask for
  // scheduled delivery every [_intervalSeconds] and thin the stream ourselves:
  // keep a point when it moved ≥[_minKeepMeters] with an acceptable accuracy
  // (≤[_maxAccuracyMeters]), or every [_heartbeat] as a liveness breadcrumb.
  static const int _intervalSeconds = 10;
  static const double _minKeepMeters = 5;
  // Drop fixes the GPS itself reports as low-quality (accuracy radius worse
  // than this) — they're jitter and make the live track look LESS accurate.
  // Looser than the server's 50m backstop (TrackingController::MAX_ACCURACY_
  // METERS); this just tightens what actually gets plotted on the live map.
  static const double _maxAccuracyMeters = 30;
  static const Duration _heartbeat = Duration(seconds: 60);
  static const int _flushBatchSize = 200;
  static const int _queueCapRows = 5000;
  static const Duration _batteryRefresh = Duration(seconds: 60);

  Database? _db;
  StreamSubscription<Position>? _positionSub;
  final Battery _battery = Battery();
  int? _cachedBatteryLevel;
  DateTime? _batteryReadAt;
  bool _flushing = false;
  bool _dead = false; // set after unrecoverable auth failure
  double? _lastKeptLat;
  double? _lastKeptLng;
  DateTime? _lastKeptAt;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // This runs in a fresh isolate: UserService's in-memory statics are empty
    // here. Rehydrate the JWT from shared_preferences so ApiService's
    // _authHeaders sees the real token.
    await UserService.init();

    _db = await openDatabase(
      '${await getDatabasesPath()}/tracking_queue.db',
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE location_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          lat REAL NOT NULL,
          lng REAL NOT NULL,
          accuracy REAL,
          speed REAL,
          heading REAL,
          battery INTEGER,
          is_mock INTEGER NOT NULL DEFAULT 0,
          recorded_at TEXT NOT NULL
        )
      '''),
    );

    _subscribeStream();
  }

  void _subscribeStream() {
    if (_dead) return;
    _positionSub?.cancel();

    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0, // we thin client-side; see _onPosition
            intervalDuration: const Duration(seconds: _intervalSeconds),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
          );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: (e) {
      print('TrackingService stream error: $e — resubscribing in 5s');
      Future.delayed(const Duration(seconds: 5), _subscribeStream);
    }, onDone: () {
      print('TrackingService stream closed — resubscribing in 5s');
      Future.delayed(const Duration(seconds: 5), _subscribeStream);
    });
  }

  double _metersBetween(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _flush();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _positionSub?.cancel();
    _positionSub = null;
    await _db?.close();
    _db = null;
  }

  // ── Capture ───────────────────────────────────────────────────────────────

  Future<void> _onPosition(Position pos) async {
    final db = _db;
    if (db == null || _dead) return;

    // Client-side thinning. Two gates, both bypassed by the 60s heartbeat so a
    // liveness breadcrumb (and the first fix after punch-in) is never starved:
    //  1. Accuracy gate — a fix the GPS reports as low-quality (accuracy radius
    //     > _maxAccuracyMeters) is jitter; plotting it makes the live track look
    //     LESS accurate, so drop it.
    //  2. Distance gate — keep only once we've moved ≥ _minKeepMeters, so a
    //     stationary phone doesn't pile up near-duplicate points.
    final now = DateTime.now();
    final heartbeatDue =
        _lastKeptAt == null || now.difference(_lastKeptAt!) >= _heartbeat;

    if (!heartbeatDue) {
      final acc = pos.accuracy;
      if (acc.isFinite && acc > _maxAccuracyMeters) {
        return;
      }
      final moved = _metersBetween(
          _lastKeptLat!, _lastKeptLng!, pos.latitude, pos.longitude);
      if (moved < _minKeepMeters) {
        return;
      }
    }

    _lastKeptLat = pos.latitude;
    _lastKeptLng = pos.longitude;
    _lastKeptAt = now;

    try {
      await db.insert('location_queue', {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy.isFinite ? pos.accuracy : null,
        'speed': pos.speed.isFinite ? pos.speed : null,
        'heading': pos.heading.isFinite ? pos.heading : null,
        'battery': await _batteryLevel(),
        'is_mock': pos.isMocked ? 1 : 0,
        // Capture-moment timestamp from the device GPS fix — NOT flush time.
        // The backend orders, gap-detects, and sets last_ping_at from this.
        'recorded_at': pos.timestamp.toUtc().toIso8601String(),
      });

      // Cap the queue so a permanently-failing upload can't grow it forever.
      await db.execute(
        'DELETE FROM location_queue WHERE id NOT IN '
        '(SELECT id FROM location_queue ORDER BY id DESC LIMIT ?)',
        [_queueCapRows],
      );
    } catch (e) {
      print('TrackingService capture error: $e');
    }
  }

  Future<int?> _batteryLevel() async {
    final now = DateTime.now();
    if (_cachedBatteryLevel != null &&
        _batteryReadAt != null &&
        now.difference(_batteryReadAt!) < _batteryRefresh) {
      return _cachedBatteryLevel;
    }
    try {
      _cachedBatteryLevel = await _battery.batteryLevel;
      _batteryReadAt = now;
    } catch (_) {}
    return _cachedBatteryLevel;
  }

  // ── Flush ─────────────────────────────────────────────────────────────────

  Future<void> _flush() async {
    final db = _db;
    if (db == null || _flushing || _dead) return;
    _flushing = true;

    try {
      final rows = await db.query(
        'location_queue',
        orderBy: 'id ASC',
        limit: _flushBatchSize,
      );
      if (rows.isEmpty) return;

      final pings = rows
          .map((r) => {
                'lat': r['lat'],
                'lng': r['lng'],
                'accuracy': r['accuracy'],
                'speed': r['speed'],
                'heading': r['heading'],
                'battery': r['battery'],
                'is_mock': (r['is_mock'] as int) == 1,
                'recorded_at': r['recorded_at'],
              })
          .toList();

      var res = await ApiService.postPings(pings);

      if (res != null && res['_status'] == 401) {
        // Token may have rotated in the main isolate — re-read from disk once.
        await UserService.init();
        res = await ApiService.postPings(pings);
        if (res != null && res['_status'] == 401) {
          await _shutdownSessionExpired();
          return;
        }
      }

      if (res != null && res['success'] == true) {
        final ids = rows.map((r) => r['id']).join(',');
        await db.execute('DELETE FROM location_queue WHERE id IN ($ids)');
      }
      // Any other outcome (null / non-2xx / network error): keep the queue,
      // retry on the next repeat event.
    } catch (e) {
      print('TrackingService flush error: $e');
    } finally {
      _flushing = false;
    }
  }

  Future<void> _shutdownSessionExpired() async {
    _dead = true;
    await _positionSub?.cancel();
    _positionSub = null;

    // Best-effort standalone notification — the foreground-service
    // notification disappears when the service stops below.
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ));
      await plugin.show(
        9101,
        'Session expired',
        'Route tracking stopped — please punch in again.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'loagma_tracking_alerts',
            'Tracking Alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      print('TrackingService expiry notification failed: $e');
    }

    await FlutterForegroundTask.stopService();
  }
}
