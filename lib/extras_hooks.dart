import 'package:flutter/material.dart';

import 'cloud_backup.dart';
import 'magic_engine.dart';
import 'magic_ui.dart';
import 'notifications.dart';
import 'stock_data.dart';
import 'stock_ui.dart';
import 'tasks_data.dart';
import 'tasks_ui.dart';

/// Glue that keeps reminders, low-stock alerts and automatic backup in step
/// with the app. Everything here is best-effort and never throws.
class ExtrasHooks {
  ExtrasHooks._();

  static DateTime? _lastRun;

  /// Called once after the first frame.
  static Future<void> onAppStart() async {
    try {
      final service = NotificationService.instance;
      service.onTapPayload = handlePayload;
      await service.init();
      await TaskStore.rescheduleAll();
      final launch = await service.launchPayload();
      if (launch != null && launch.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        handlePayload(launch);
      }
    } catch (e) {
      debugPrint('Extras start failed: $e');
    }
  }

  /// Called when the Home screen loads and when the app returns to the
  /// foreground. Debounced so it stays light.
  static void onHomeLoaded({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        _lastRun != null &&
        now.difference(_lastRun!) < const Duration(seconds: 20)) {
      return;
    }
    _lastRun = now;
    () async {
      try {
        await MagicEngine.refresh();
        await StockStore.checkLowStock();
        await CloudBackup.instance.autoBackupIfDue();
      } catch (e) {
        debugPrint('Extras refresh failed: $e');
      }
    }();
  }

  static void handlePayload(String payload) {
    final nav = extrasNavigatorKey.currentState;
    if (nav == null) return;
    if (payload.startsWith('task:')) {
      nav.push(MaterialPageRoute(builder: (_) => const TasksPage()));
    } else if (payload == 'magic') {
      nav.push(MaterialPageRoute(builder: (_) => const MagicReminderPage()));
    } else if (payload == 'stock') {
      nav.push(MaterialPageRoute(builder: (_) => const ChemicalStockPage()));
    }
  }
}

/// Re-checks reminders and automatic backup when the app comes back.
class ExtrasLifecycle with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ExtrasHooks.onHomeLoaded();
    }
  }
}
