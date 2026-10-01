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
      try {
        await android?.requestExactAlarmsPermission();
      } catch (_) {}
      return granted ?? true;
    } catch (e) {
      debugPrint('Permission request failed: $e');
      return false;
    }
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'farmbook_reminders_v2',
        'FarmBook reminders',
        channelDescription: 'Task and Magic Reminder notifications',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        playSound: true,
        enableVibration: true,
        ticker: 'FarmBook reminder',
        styleInformation: BigTextStyleInformation(''),
      ),
    );
  }

  /// Schedules a notification at [when] (device local time). Times in the
  /// past are ignored. A notification with the same [id] is replaced.
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String payload = '',
  }) async {
    try {
      await init();
      if (!_ready) return;
      if (when.isBefore(DateTime.now().add(const Duration(seconds: 10)))) {
        return;
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
          _details(),
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
    } catch (e) {
      debugPrint('Schedule failed: $e');
    }
  }

  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String payload = '',
  }) async {
    try {
      await init();
      if (!_ready) return;
      await _plugin.show(id, title, body, _details(), payload: payload);
    } catch (e) {
      debugPrint('Show failed: $e');
    }
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
