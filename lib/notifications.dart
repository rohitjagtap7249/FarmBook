import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Lets notification taps open screens from anywhere in the app.
final GlobalKey<NavigatorState> extrasNavigatorKey =
    GlobalKey<NavigatorState>();

/// Thin wrapper around flutter_local_notifications.
///
/// Notifications are scheduled ahead of time as absolute instants, so they
/// still fire when FarmBook is closed. Nothing here ever creates or edits a
/// farm record.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Called with the notification payload when the user taps a notification.
  void Function(String payload)? onTapPayload;

  /// Last problem seen while showing or scheduling (shown in diagnostics).
  String lastError = '';

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        const InitializationSettings(android: android),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            onTapPayload?.call(payload);
          }
        },
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  /// Payload of the notification that launched the app from a closed state.
  Future<String?> launchPayload() async {
    try {
      await init();
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details != null && details.didNotificationLaunchApp) {
        return details.notificationResponse?.payload;
      }
    } catch (e) {
      debugPrint('Launch details failed: $e');
    }
    return null;
  }

  Future<bool> requestPermission() async {
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (e) {
      debugPrint('Permission request failed: $e');
      return false;
    }
  }

  /// A normal notification, like payment or shopping apps send: a banner at
  /// the top of the screen, default sound, and an entry in the notification
  /// shade. No alarm sound and no full-screen takeover.
  NotificationDetails _details(String body) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'farmbook_reminders_v3',
        'FarmBook reminders',
        channelDescription: 'Task and Magic Reminder notifications',
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.public,
        styleInformation: BigTextStyleInformation(body),
      ),
    );
  }

  /// Schedules a notification at [when] (device local time). Times in the
  /// past are ignored. A notification with the same [id] is replaced.
  Future<bool> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String payload = '',
  }) async {
    try {
      await init();
      if (!_ready) {
        lastError = 'Notifications could not start.';
        return false;
      }
      if (when.isBefore(DateTime.now().add(const Duration(seconds: 2)))) {
        return false;
      }
      final u = when.toUtc();
      final scheduled =
          tz.TZDateTime.utc(u.year, u.month, u.day, u.hour, u.minute, u.second);
      Future<void> go(AndroidScheduleMode mode) {
        return _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduled,
          _details(body),
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
      }

      try {
        // Exact timing so the reminder pops up at the chosen minute.
        await go(AndroidScheduleMode.exactAllowWhileIdle);
      } catch (_) {
        // Exact alarms not allowed on this phone: fall back to a close time.
        await go(AndroidScheduleMode.inexactAllowWhileIdle);
      }
      return true;
    } catch (e) {
      lastError = 'Schedule failed: $e';
      debugPrint(lastError);
      return false;
    }
  }

  Future<bool> showNow({
    required int id,
    required String title,
    required String body,
    String payload = '',
  }) async {
    try {
      await init();
      if (!_ready) {
        lastError = 'Notifications could not start.';
        return false;
      }
      await _plugin.show(id, title, body, _details(body), payload: payload);
      return true;
    } catch (e) {
      lastError = 'Show failed: $e';
      debugPrint(lastError);
      return false;
    }
  }

  /// Plain-language status used by the "Check reminders" dialog.
  Future<String> diagnose() async {
    final lines = <String>[];
    try {
      await init();
      lines.add('Started: ${_ready ? 'yes' : 'NO'}');
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await android?.areNotificationsEnabled();
      lines.add('Notifications allowed: ${enabled == null ? '?' : (enabled ? 'yes' : 'NO')}');
      try {
        final exact = await android?.canScheduleExactNotifications();
        lines.add('Exact alarms allowed: ${exact == null ? '?' : (exact ? 'yes' : 'no')}');
      } catch (_) {}
      final probe = await schedule(
        id: 999997,
        title: 'probe',
        body: 'probe',
        when: DateTime.now().add(const Duration(hours: 1)),
      );
      lines.add('Scheduling test: ${probe ? 'OK' : 'FAILED'}');
      if (probe) await _plugin.cancel(999997);
      final pending = await _plugin.pendingNotificationRequests();
      lines.add('Reminders waiting: ${pending.length}');
    } catch (e) {
      lines.add('Check failed: $e');
    }
    lines.add('Last problem: ${lastError.isEmpty ? 'none' : lastError}');
    return lines.join('\n');
  }

  Future<void> cancel(int id) async {
    try {
      await init();
      if (!_ready) return;
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('Cancel failed: $e');
    }
  }
}
