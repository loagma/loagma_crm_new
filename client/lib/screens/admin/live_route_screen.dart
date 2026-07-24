import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api_service.dart';
import '../../utils/distance_format.dart';

/// Admin: watch one salesman's route grow live on the map.
///
/// First load draws the full trail for today; afterwards a delta poll every
/// 5s (?since=<last recorded_at>) appends only new points. Polling stops when
/// the salesman punches out (is_active false) or the screen is disposed.
///
/// Map polish: new points are not teleported — the vehicle marker glides
/// through them (~1.5s per batch, split across points) with the polyline
/// extending in sync, the icon rotating via shortest-arc to the ping heading.
/// A halo pulses under the marker while LIVE, and a translucent circle shows
/// GPS accuracy in meters. Interruption gaps (>5 min) are never glided
/// across — the marker jumps, honestly, exactly like the distance rule.
class LiveRouteScreen extends StatefulWidget {
  final String mobile;
  final String name;

  const LiveRouteScreen({super.key, required this.mobile, required this.name});

  @override
  State<LiveRouteScreen> createState() => _LiveRouteScreenState();
}

class _LiveRouteScreenState extends State<LiveRouteScreen>
    with TickerProviderStateMixin {
  static const _gold = Color(0xFFD7BE69);
  static const _routeColor = Color(0xFF2F6FED);
  // Darker shade of the route blue, drawn as an outline under the main line.
  static const _routeOutline = Color(0xFF1C4CB3);

  final MapController _mapController = MapController();

  // Matches RouteDistance::GAP_MINUTES server-side: a longer silence is an
  // interruption — the jump across it is not counted as walked distance.
  static const _gapRule = Duration(minutes: 5);

  // Item 2: one delta batch animates over ~1.5s total, split across its
  // points; a single segment never runs faster than _minSegmentMs. A huge
  // backlog (offline flush) is committed instantly except the tail — gliding
  // through 50 points in 1.5s would just look like a glitchy sprint.
  static const _batchAnimMs = 1500;
  static const _minSegmentMs = 120;
  static const _maxAnimatedBacklog = 24;

  // Below ~1 m/s the GPS heading is noise — keep the last known heading.
  static const _movingSpeedMs = 1.0;
  // Accuracy better than this needs no hedge circle on screen.
  static const _accuracyHideBelowM = 15.0;

  Timer? _timer;

  /// Points already drawn (committed). The animated tip extends past the
  /// last committed point while a segment is in flight.
  final List<LatLng> _points = [];
  final List<_IncomingPoint> _animQueue = [];
  DateTime? _lastCommittedAt;

  LatLng? _tip; // displayed marker position (interpolated mid-segment)
  double _displayHeading = 0;
  double? _tipAccuracy;

  // Last RECEIVED point — distance accumulates on arrival, independent of
  // how far the display animation has caught up.
  LatLng? _lastReceived;
  DateTime? _lastReceivedAt;

  String? _lastRecordedAt;
  double _distanceKm = 0;
  bool _hasGaps = false;
  LatLng? _start; // punch-in location (green pin)
  bool _isActive = true;
  bool _loading = true;
  String? _error;
  bool _followTip = true;

  AnimationController? _moveCtrl;
  AnimationController? _camCtrl;
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  bool get _animating => _moveCtrl?.isAnimating ?? false;

  @override
  void initState() {
    super.initState();
    _fetch(initial: true);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _moveCtrl?.dispose();
    _camCtrl?.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool initial = false}) async {
    if (!_isActive && !initial) return;

    final res = await ApiService.getLiveRoute(
      mobile: widget.mobile,
      since: initial ? null : _lastRecordedAt,
    );
    if (!mounted) return;

    if (res == null || res['success'] != true) {
      setState(() {
        _loading = false;
        if (initial) _error = 'Could not load route';
      });
      return;
    }

    final data = res['data'] as Map<String, dynamic>;
    final incoming = (data['points'] as List).cast<Map<String, dynamic>>();
    // A request without ?since= returned the full trail — the server's
    // distance covers exactly these points. Deltas extend the sum locally.
    final fullFetch = _lastRecordedAt == null;

    final fresh = <_IncomingPoint>[];

    setState(() {
      _loading = false;
      _error = null;

      final startRaw = data['start'];
      if (startRaw is Map && startRaw['lat'] != null) {
        _start = LatLng(
          (startRaw['lat'] as num).toDouble(),
          (startRaw['lng'] as num).toDouble(),
        );
      }

      for (final p in incoming) {
        final pt = LatLng(
          (p['lat'] as num).toDouble(),
          (p['lng'] as num).toDouble(),
        );
        final at = DateTime.tryParse(p['recorded_at'] as String? ?? '');

        if (!fullFetch && _lastReceived != null && at != null && _lastReceivedAt != null) {
          if (at.difference(_lastReceivedAt!) > _gapRule) {
            _hasGaps = true; // interrupted — do not count the jump
          } else {
            _distanceKm +=
                const Distance().as(LengthUnit.Kilometer, _lastReceived!, pt);
          }
        }

        fresh.add(_IncomingPoint(
          pt: pt,
          at: at,
          heading: (p['heading'] as num?)?.toDouble(),
          speed: (p['speed'] as num?)?.toDouble(),
          accuracy: (p['accuracy'] as num?)?.toDouble(),
        ));

        _lastReceived = pt;
        if (at != null) _lastReceivedAt = at;
        _lastRecordedAt = p['recorded_at'] as String;
      }

      if (fullFetch) {
        _distanceKm = (data['distance_km'] as num?)?.toDouble() ?? 0;
        _hasGaps = data['has_gaps'] == true;
        // Draw the whole existing trail instantly — only NEW points animate.
        for (final f in fresh) {
          _points.add(f.pt);
          _lastCommittedAt = f.at ?? _lastCommittedAt;
          _tipAccuracy = f.accuracy ?? _tipAccuracy;
        }
        if (_points.isNotEmpty) _tip = _points.last;
        if (_points.length >= 2) {
          _displayHeading = _bearing(
            _points[_points.length - 2],
            _points.last,
          );
        }
        fresh.clear();
      }

      final wasActive = _isActive;
      _isActive = data['is_active'] == true;
      if (wasActive && !_isActive) {
        _timer?.cancel();
        _pulseCtrl.stop(); // ENDED: halo freezes (item 3)
      }
    });

    if (fresh.isNotEmpty) {
      _animQueue.addAll(fresh);
      _pumpQueue();
      // Everything was committed instantly (e.g. a gap teleport): the marker
      // moved without animation ticks, so ease the camera over in one go.
      if (!_animating && _followTip && _tip != null) {
        _easeCameraTo(_tip!);
      }
    }
  }

  // ─── Item 2: sequential segment animation ────────────────────────────────

  void _pumpQueue() {
    if (!mounted || _animating || _animQueue.isEmpty) return;

    // Offline backlog: fast-forward all but the last few points.
    while (_animQueue.length > _maxAnimatedBacklog) {
      _commit(_animQueue.removeAt(0));
    }

    final next = _animQueue.removeAt(0);
    final from = _tip ?? (_points.isNotEmpty ? _points.last : next.pt);

    // Honesty rule: an interruption gap is a jump, not a glide.
    final isGapJump = next.at != null &&
        _lastCommittedAt != null &&
        next.at!.difference(_lastCommittedAt!) > _gapRule;
    if (isGapJump || _points.isEmpty) {
      setState(() => _commit(next));
      _pumpQueue();
      return;
    }

    final segMs = math.max(
      _minSegmentMs,
      _batchAnimMs ~/ (_animQueue.length + 1),
    );
    _animateSegment(from, next, segMs);
  }

  void _animateSegment(LatLng from, _IncomingPoint target, int ms) {
    _moveCtrl?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    );
    _moveCtrl = ctrl;

    final latTween =
        Tween<double>(begin: from.latitude, end: target.pt.latitude);
    final lngTween =
        Tween<double>(begin: from.longitude, end: target.pt.longitude);
    final headingFrom = _displayHeading;
    // Shortest-arc so the icon never spins 350° the wrong way (item 2).
    final headingDelta =
        _shortestArc(headingFrom, _targetHeading(target, from));

    ctrl.addListener(() {
      if (!mounted) return;
      final t = ctrl.value; // linear: chained segments stay seamless
      setState(() {
        _tip = LatLng(latTween.transform(t), lngTween.transform(t));
        _displayHeading = (headingFrom + headingDelta * t + 360) % 360;
      });
      // Item 6: follow camera rides the same animation — smooth by nature.
      if (_followTip && _tip != null) {
        _mapController.move(_tip!, _mapController.camera.zoom);
      }
    });
    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (!mounted) return;
        setState(() => _commit(target));
        _pumpQueue();
      }
    });
    ctrl.forward();
  }

  void _commit(_IncomingPoint p) {
    _points.add(p.pt);
    _tip = p.pt;
    _lastCommittedAt = p.at ?? _lastCommittedAt;
    if (p.accuracy != null) _tipAccuracy = p.accuracy;
  }

  // ─── Item 1: heading rules ───────────────────────────────────────────────

  /// heading when moving (>~1 m/s); below that keep the LAST heading — GPS
  /// heading is noise when stationary. Null heading → bearing from the last
  /// two points, but only if they are far enough apart to carry a direction.
  double _targetHeading(_IncomingPoint p, LatLng from) {
    final distM = const Distance().as(LengthUnit.Meter, from, p.pt);
    final moving =
        p.speed != null ? p.speed! > _movingSpeedMs : distM > 5;
    if (!moving) return _displayHeading;
    if (p.heading != null) return p.heading!;
    if (distM < 3) return _displayHeading;
    return _bearing(from, p.pt);
  }

  static double _bearing(LatLng from, LatLng to) =>
      (const Distance().bearing(from, to) + 360) % 360;

  static double _shortestArc(double from, double to) =>
      ((to - from + 540) % 360) - 180;

  // ─── Item 6: eased camera ────────────────────────────────────────────────

  void _easeCameraTo(LatLng dest) {
    _camCtrl?.dispose();
    final camera = _mapController.camera;
    final latTween = Tween<double>(begin: camera.center.latitude, end: dest.latitude);
    final lngTween = Tween<double>(begin: camera.center.longitude, end: dest.longitude);
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _camCtrl = ctrl;
    final anim = CurvedAnimation(parent: ctrl, curve: Curves.easeInOut);
    ctrl.addListener(() {
      if (!mounted) return;
      _mapController.move(
        LatLng(latTween.evaluate(anim), lngTween.evaluate(anim)),
        camera.zoom,
      );
    });
    ctrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Flexible(
              child: Text(widget.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _isActive ? const Color(0xFF2F9E57) : Colors.redAccent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_isActive ? 'LIVE' : 'ENDED',
                  style: const TextStyle(fontSize: 11, color: Colors.white)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Route history',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/route-history', extra: {
              'mobile': widget.mobile,
              'name': widget.name,
            }),
          ),
          IconButton(
            tooltip: _followTip ? 'Following position' : 'Free camera',
            icon: Icon(_followTip ? Icons.gps_fixed : Icons.gps_not_fixed),
            onPressed: () {
              setState(() => _followTip = !_followTip);
              // Re-enabling follow eases back to the tip instead of snapping.
              if (_followTip && _tip != null) _easeCameraTo(_tip!);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (!_loading && _error == null)
            Positioned(left: 0, right: 0, bottom: 0, child: _distanceStrip()),
        ],
      ),
    );
  }

  /// Bottom strip: running distance, extended client-side on each delta poll.
  Widget _distanceStrip() {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.straighten, size: 20, color: _routeColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatDistance(_distanceKm, hasGaps: _hasGaps),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (_hasGaps)
                    Text(
                      kGapWarningText,
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange.shade800),
                    ),
                ],
              ),
            ),
            Text(
              '${_points.length} pts',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: Colors.grey.shade600)));
    }
    if (_points.isEmpty && _start == null) {
      return Center(
        child: Text('No route points yet today',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
      );
    }

    final tip = _tip ?? (_points.isNotEmpty ? _points.last : null);
    final center = tip ?? _start!;
    // The trail plus the in-flight tip — the line extends WITH the marker,
    // never ahead of it (item 2).
    final trail = <LatLng>[
      ..._points,
      if (tip != null && (_points.isEmpty || tip != _points.last)) tip,
    ];

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16,
        onPositionChanged: (camera, hasGesture) {
          // Manual pan hands the camera to the admin; the toolbar toggle
          // re-enables following (item 6).
          if (hasGesture && _followTip) setState(() => _followTip = false);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.client',
        ),
        // Item 4: GPS accuracy as a real-meter circle; a good fix (<15m)
        // needs no hedge on screen.
        if (_isActive &&
            tip != null &&
            _tipAccuracy != null &&
            _tipAccuracy! >= _accuracyHideBelowM)
          CircleLayer(circles: [
            CircleMarker(
              point: tip,
              radius: _tipAccuracy!,
              useRadiusInMeter: true,
              color: _routeColor.withValues(alpha: 0.10),
              borderColor: _routeColor.withValues(alpha: 0.25),
              borderStrokeWidth: 1,
            ),
          ]),
        if (trail.length >= 2)
          PolylineLayer(polylines: [
            // Item 5: darker outline under the main line, rounded joins.
            Polyline(
              points: trail,
              strokeWidth: 5,
              color: _routeColor,
              borderStrokeWidth: 2.5,
              borderColor: _routeOutline,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          ]),
        MarkerLayer(markers: [
          if (_start != null)
            Marker(
              point: _start!,
              width: 36,
              height: 36,
              child: const Icon(Icons.trip_origin, color: Color(0xFF2F9E57), size: 28),
            ),
          if (tip != null)
            _isActive
                ? Marker(
                    point: tip,
                    width: 76,
                    height: 76,
                    child: _liveVehicleMarker(),
                  )
                : Marker(
                    point: tip,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_on,
                        color: Colors.redAccent, size: 34),
                  ),
        ]),
      ],
    );
  }

  // ─── Items 1 + 3: vehicle marker with pulsing halo ───────────────────────

  Widget _liveVehicleMarker() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_pulseCtrl.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            // Soft halo expanding out from under the icon while LIVE.
            Container(
              width: 44 + 32 * t,
              height: 44 + 32 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _routeColor.withValues(alpha: 0.25 * (1 - t)),
              ),
            ),
            child!,
          ],
        );
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _rotatedBike(),
      ),
    );
  }

  /// The two_wheeler glyph faces EAST natively. Rotate it to the display
  /// heading, mirroring when travelling westish so the bike is never drawn
  /// upside-down (the same trick delivery apps use for side-profile icons).
  Widget _rotatedBike() {
    final flip = _displayHeading > 180;
    final angleDeg = flip ? _displayHeading + 90 : _displayHeading - 90;
    return Transform.rotate(
      angle: angleDeg * math.pi / 180,
      child: Transform.flip(
        flipX: flip,
        child: const Icon(Icons.two_wheeler, color: _routeColor, size: 27),
      ),
    );
  }
}

/// A freshly received route point queued for the tip animation.
class _IncomingPoint {
  final LatLng pt;
  final DateTime? at;
  final double? heading;
  final double? speed;
  final double? accuracy;

  const _IncomingPoint({
    required this.pt,
    required this.at,
    required this.heading,
    required this.speed,
    required this.accuracy,
  });
}
