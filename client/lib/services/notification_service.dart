import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Manages follow-up reminders. Each follow-up gets three scheduled
/// notifications: 1 hour, 10 minutes, and 5 minutes before the due time.
/// Reminders are cancelled when the outcome is logged or the follow-up is
/// marked done.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();
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

  /// Schedule 3 reminders for a follow-up: 1 hr, 10 min, 5 min before.
  /// Only reminders whose fire time is still in the future are scheduled.
  /// Cancels any existing reminders for the same account first.
  static Future<void> scheduleFollowUpReminders(
    String accountId,
    String name,
    DateTime followUpTime,
  ) async {
    if (!_initialized) return;
    try {
      await cancelFollowUpReminders(accountId);

      final base = _notifBase(accountId);
      final now  = DateTime.now();

      final reminders = [
        (base,     const Duration(hours: 1),    '1 hour'),
        (base + 1, const Duration(minutes: 10), '10 minutes'),
        (base + 2, const Duration(minutes: 5),  '5 minutes'),
      ];

      for (final (id, before, label) in reminders) {
        final fireAt = followUpTime.subtract(before);
        if (fireAt.isAfter(now)) {
          await _scheduleOne(
            id: id,
            title: 'Follow-up in $label',
            body: name,
            scheduledTime: fireAt,
          );
        }
      }
    } catch (e) {
      debugPrint('NotificationService.scheduleFollowUpReminders error: $e');
    }
  }

  /// Cancel all scheduled reminders for an account (call when outcome is
  /// saved, follow-up is marked done, or a new follow-up replaces the old one).
  static Future<void> cancelFollowUpReminders(String accountId) async {
    if (!_initialized) return;
    try {
      final base = _notifBase(accountId);
      await _plugin.cancel(base);
      await _plugin.cancel(base + 1);
      await _plugin.cancel(base + 2);
    } catch (e) {
      debugPrint('NotificationService.cancelFollowUpReminders error: $e');
    }
  }

  /// Stable 3-slot notification base ID for an account.
  /// Multiplied by 3 so three consecutive IDs (base, base+1, base+2) are safe.
  static int _notifBase(String accountId) {
    final n = int.tryParse(accountId);
    final raw = n ?? accountId.hashCode.abs();
    return (raw % 333333) * 3 + 100; // +100 avoids old hard-coded IDs 1 & 2
  }

  static Future<void> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
    final android = AndroidNotificationDetails(
      'followup_channel',
      'Follow-up Reminders',
      channelDescription: 'Reminders for due and overdue follow-ups',
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      NotificationDetails(android: android, iOS: ios),
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
