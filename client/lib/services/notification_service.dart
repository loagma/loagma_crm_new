import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: iOS),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  /// Call this when the telecaller opens the worklist.
  /// Fetches due/overdue follow-ups and fires local notifications.
  static Future<void> checkFollowUps() async {
    if (!_initialized) return;
    try {
      final callbacks = await ApiService.getTelecallerCallbacks();
      if (callbacks.isEmpty) return;

      final overdue = callbacks.where((c) => c['overdue'] == true).toList();
      final dueToday = callbacks.where((c) => c['overdue'] != true).toList();

      await _plugin.cancelAll();

      if (overdue.isNotEmpty) {
        final names = overdue.take(3).map((c) => '${c['name'] ?? 'Unknown'}').join(', ');
        await _show(
          id: 1,
          title: '${overdue.length} Overdue Follow-up${overdue.length > 1 ? 's' : ''}',
          body: names,
          color: const Color(0xFFE53935),
        );
      }

      if (dueToday.isNotEmpty) {
        final names = dueToday.take(3).map((c) => '${c['name'] ?? 'Unknown'}').join(', ');
        await _show(
          id: 2,
          title: '${dueToday.length} Follow-up${dueToday.length > 1 ? 's' : ''} due today',
          body: names,
          color: const Color(0xFFD7BE69),
        );
      }
    } catch (_) {}
  }

  static Future<void> _show({
    required int id,
    required String title,
    required String body,
    required Color color,
  }) async {
    final android = AndroidNotificationDetails(
      'followup_channel',
      'Follow-up Reminders',
      channelDescription: 'Reminders for due and overdue follow-ups',
      importance: Importance.high,
      priority: Priority.high,
      color: color,
    );
    await _plugin.show(id, title, body, NotificationDetails(android: android));
  }
}
