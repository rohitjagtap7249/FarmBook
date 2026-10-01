import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'notifications.dart';

const List<String> kMagicActivities = [
  'spray',
  'drip',
  'labour',
  'other',
  'earnings',
];

String magicActivityLabel(String activity) {
  switch (activity) {
    case 'spray':
      return 'Spray';
    case 'drip':
      return 'Drip Application';
    case 'labour':
      return 'Labour';
    case 'other':
      return 'Other Expenses';
    case 'earnings':
      return 'Earnings';
    default:
      return activity;
  }
}

/// A learned repeating interval, in days.
class PatternResult {
  const PatternResult(this.intervalDays, this.intervalsUsed);
  final int intervalDays;
  final int intervalsUsed;
}

/// Current state of one watched (activity, plot, chemical) combination.
class ReminderItem {
  ReminderItem({
    required this.key,
    required this.mode,
    required this.activity,
    required this.plotId,
    required this.plotTitle,
    required this.chemical,
    required this.datesCount,
    required this.status,
    this.last,
    this.intervalDays,
    this.dueAt,
    this.daysSince,
    this.manual = false,
  });

  final String key;
  final String mode; // 'pattern' | 'pulse'
  final String activity;
  final int plotId;
  final String plotTitle;
  final String chemical;
  final int datesCount;

  /// 'learning' | 'watching' | 'due' | 'inactive'
  final String status;
  final DateTime? last;
  final int? intervalDays;
  final DateTime? dueAt;
  final int? daysSince;

  /// True when the farmer set the frequency by hand instead of letting
  /// FarmBook learn it from the records.
  final bool manual;
}

String _monthDay(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

int _stableHash(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Wording is deliberately soft: reminders only say the farmer may want to
/// check a plot. They never claim an activity is required or completed.
String reminderBody(ReminderItem it, {bool includeDaysSince = false}) {
  final what = it.activity == 'spray' && it.chemical.isNotEmpty
      ? '${it.chemical} was last recorded on ${it.plotTitle}'
      : '${magicActivityLabel(it.activity)} was last recorded on ${it.plotTitle}';
  final lastTxt = it.last == null ? '' : ' on ${_monthDay(it.last!)}';
  final gap = it.intervalDays == null
      ? ''
      : (it.manual
          ? ' You set this to repeat every ${it.intervalDays} days.'
          : ' Your recent records were about ${it.intervalDays} days apart.');
  final since = (includeDaysSince && it.daysSince != null)
      ? ' It has now been ${it.daysSince} days.'
      : '';
  return '$what$lastTxt.$gap$since You may want to check this plot.';
}

class MagicEngine {
  MagicEngine._();

  // ---------------------------------------------------------------
  // Settings helpers (existing app_settings key/value table)
  // ---------------------------------------------------------------

  static Future<String?> _get(String key) async {
    final db = await AppDatabase.instance.database;
    final rows =
        await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  static Future<void> _set(String key, String value) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------
  // Rules
  // ---------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> rules() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT r.*, p.title AS plot_title
      FROM reminder_rules r LEFT JOIN plots p ON p.id = r.plot_id
      ORDER BY r.mode ASC, r.activity ASC, r.id ASC
    ''');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  static Future<void> addPatternRule({
    required String activity,
    required int plotId,
    String chemical = '',
    int? intervalDays,
  }) async {
    final db = await AppDatabase.instance.database;
    final existing = await db.query(
      'reminder_rules',
      where: "mode = 'pattern' AND activity = ? AND plot_id = ? "
          'AND chemical_name = ? COLLATE NOCASE',
      whereArgs: [activity, plotId, chemical],
    );
    if (existing.isNotEmpty) {
      await db.update(
        'reminder_rules',
        {'enabled': 1, 'interval_days': intervalDays},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
      return;
    }
    await db.insert('reminder_rules', {
      'mode': 'pattern',
      'activity': activity,
      'plot_id': plotId,
      'chemical_name': chemical,
      'interval_days': intervalDays,
      'enabled': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> setPulse(String activity, bool enabled) async {
    final db = await AppDatabase.instance.database;
    final existing = await db.query(
      'reminder_rules',
      where: "mode = 'pulse' AND activity = ?",
      whereArgs: [activity],
    );
    if (existing.isEmpty) {
      if (!enabled) return;
      await db.insert('reminder_rules', {
        'mode': 'pulse',
        'activity': activity,
        'plot_id': null,
        'chemical_name': '',
        'enabled': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      await db.update(
        'reminder_rules',
        {'enabled': enabled ? 1 : 0},
        where: "mode = 'pulse' AND activity = ?",
        whereArgs: [activity],
      );
    }
  }

  static Future<void> setRuleEnabled(int id, bool enabled) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'reminder_rules',
      {'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> setPatternActivityEnabled(
    String activity,
    bool enabled,
  ) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'reminder_rules',
      {'enabled': enabled ? 1 : 0},
      where: "mode = 'pattern' AND activity = ?",
      whereArgs: [activity],
    );
  }

  static Future<void> deleteRule(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('reminder_rules', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------
  // Pattern learning
  // ---------------------------------------------------------------

  /// Learns a repeating interval from activity dates (sorted ascending,
  /// one entry per day). Conservative: needs at least two matching
  /// intervals; irregular history returns null.
  static PatternResult? analyze(List<DateTime> dates) {
    if (dates.length < 3) return null;
    final intervals = <int>[];
    for (var i = 1; i < dates.length; i++) {
      final gap = dates[i].difference(dates[i - 1]).inDays;
      if (gap >= 1) intervals.add(gap);
    }
    if (intervals.length < 2) return null;
    final recent = intervals.length > 6
        ? intervals.sublist(intervals.length - 6)
        : intervals;
    final sorted = [...recent]..sort();
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2.0;
    if (median < 1) return null;
    final tolerance = median * 0.3 < 1 ? 1.0 : median * 0.3;
    final consistent =
        recent.where((g) => (g - median).abs() <= tolerance).length;
    if (consistent < 2) return null;
    if (consistent < (recent.length * 0.6).ceil()) return null;
    return PatternResult(median.round(), recent.length);
  }

  static Future<List<DateTime>> _dates(
    String activity,
    int plotId,
    String chemical,
  ) async {
    final db = await AppDatabase.instance.database;
    List<Map<String, Object?>> rows;
    switch (activity) {
      case 'spray':
        rows = await db.rawQuery('''
          SELECT s.spray_date AS d FROM sprays s
          JOIN spray_chemicals sc ON sc.spray_id = s.id
          WHERE s.plot_id = ? AND sc.chemical_name = ? COLLATE NOCASE
        ''', [plotId, chemical]);
        break;
      case 'drip':
        rows = await db.rawQuery(
          'SELECT drip_date AS d FROM drip_applications WHERE plot_id = ?',
          [plotId],
        );
        break;
      case 'labour':
        rows = await db.rawQuery(
          'SELECT labour_date AS d FROM labour_records WHERE plot_id = ?',
          [plotId],
        );
        break;
      case 'other':
        rows = await db.rawQuery(
          'SELECT expense_date AS d FROM other_expenses WHERE plot_id = ?',
          [plotId],
        );
        break;
      case 'earnings':
        rows = await db.rawQuery(
          'SELECT earning_date AS d FROM earnings WHERE plot_id = ?',
          [plotId],
        );
        break;
      default:
        rows = [];
    }
    final days = <DateTime>{};
    for (final r in rows) {
      final parsed = DateTime.tryParse(r['d'].toString());
      if (parsed == null) continue;
      days.add(DateTime.utc(parsed.year, parsed.month, parsed.day));
    }
    final list = days.toList()..sort();
    return list;
  }

  /// (plotId, chemical) combinations FarmPulse should look at.
  static Future<List<List<Object>>> _pulseCombos(String activity) async {
    final db = await AppDatabase.instance.database;
    final out = <List<Object>>[];
    if (activity == 'spray') {
      final rows = await db.rawQuery('''
        SELECT s.plot_id AS plot_id, MIN(sc.chemical_name) AS chem
        FROM sprays s JOIN spray_chemicals sc ON sc.spray_id = s.id
        GROUP BY s.plot_id, sc.chemical_name COLLATE NOCASE
      ''');
      for (final r in rows) {
        out.add([r['plot_id'] as int, r['chem'].toString()]);
      }
      return out;
    }
    final table = {
      'drip': 'drip_applications',
      'labour': 'labour_records',
      'other': 'other_expenses',
      'earnings': 'earnings',
    }[activity];
    if (table == null) return out;
    final rows = await db.rawQuery('SELECT DISTINCT plot_id FROM $table');
    for (final r in rows) {
      out.add([r['plot_id'] as int, '']);
    }
    return out;
  }

  static Future<ReminderItem> _build({
    required String mode,
    required String activity,
    required int plotId,
    required String plotTitle,
    required String chemical,
    int? manualInterval,
  }) async {
    final key = '$activity|$plotId|${chemical.toLowerCase()}';
    final dates = await _dates(activity, plotId, chemical);
    if (manualInterval != null && manualInterval >= 1) {
      return _buildManual(
        key: key,
        mode: mode,
        activity: activity,
        plotId: plotId,
        plotTitle: plotTitle,
        chemical: chemical,
        dates: dates,
        interval: manualInterval,
      );
    }
    final result = analyze(dates);
    if (result == null || dates.isEmpty) {
      return ReminderItem(
        key: key,
        mode: mode,
        activity: activity,
        plotId: plotId,
        plotTitle: plotTitle,
        chemical: chemical,
        datesCount: dates.length,
        status: 'learning',
        last: dates.isEmpty ? null : dates.last,
      );
    }
    final last = dates.last;
    final interval = result.intervalDays;
    final grace = (interval * 0.2).round() < 1 ? 1 : (interval * 0.2).round();
    final dueAt = DateTime(
      last.year,
      last.month,
      last.day + interval + grace,
      8,
      0,
    );
    final now = DateTime.now();
    final todayUtc = DateTime.utc(now.year, now.month, now.day);
    final daysSince = todayUtc.difference(last).inDays;
    String status;
    if (now.isBefore(dueAt)) {
      status = 'watching';
    } else if (daysSince <= interval * 4 && daysSince <= 120) {
      status = 'due';
    } else {
      status = 'inactive';
    }
    return ReminderItem(
      key: key,
      mode: mode,
      activity: activity,
      plotId: plotId,
      plotTitle: plotTitle,
      chemical: chemical,
      datesCount: dates.length,
      status: status,
      last: last,
      intervalDays: interval,
      dueAt: dueAt,
      daysSince: daysSince,
    );
  }

  /// Fixed frequency chosen by the farmer: needs only one past record.
  static ReminderItem _buildManual({
    required String key,
    required String mode,
    required String activity,
    required int plotId,
    required String plotTitle,
    required String chemical,
    required List<DateTime> dates,
    required int interval,
  }) {
    if (dates.isEmpty) {
      return ReminderItem(
        key: key,
        mode: mode,
        activity: activity,
        plotId: plotId,
        plotTitle: plotTitle,
        chemical: chemical,
        datesCount: 0,
        status: 'learning',
        intervalDays: interval,
        manual: true,
      );
    }
    final last = dates.last;
    final dueAt = DateTime(last.year, last.month, last.day + interval, 8, 0);
    final now = DateTime.now();
    final todayUtc = DateTime.utc(now.year, now.month, now.day);
    final daysSince = todayUtc.difference(last).inDays;
    String status;
    if (now.isBefore(dueAt)) {
      status = 'watching';
    } else if (daysSince <= interval * 4 && daysSince <= 180) {
      status = 'due';
    } else {
      status = 'inactive';
    }
    return ReminderItem(
      key: key,
      mode: mode,
      activity: activity,
      plotId: plotId,
      plotTitle: plotTitle,
      chemical: chemical,
      datesCount: dates.length,
      status: status,
      last: last,
      intervalDays: interval,
      dueAt: dueAt,
      daysSince: daysSince,
      manual: true,
    );
  }

  /// Evaluates every enabled rule. Read-only: never writes farm records.
  static Future<List<ReminderItem>> evaluate() async {
    final db = await AppDatabase.instance.database;
    final rules = await db.query('reminder_rules', where: 'enabled = 1');
    final plotRows = await AppDatabase.instance.getPlots();
    final plots = <int, String>{
      for (final p in plotRows) p['id'] as int: p['title'].toString(),
    };
    final byKey = <String, ReminderItem>{};

    for (final r in rules.where((r) => r['mode'] == 'pattern')) {
      final plotId = r['plot_id'] as int?;
      if (plotId == null || !plots.containsKey(plotId)) continue;
      final activity = r['activity'].toString();
      final chem = r['chemical_name'].toString();
      if (activity == 'spray' && chem.isEmpty) continue;
      final item = await _build(
        mode: 'pattern',
        activity: activity,
        plotId: plotId,
        plotTitle: plots[plotId]!,
        chemical: chem,
        manualInterval: r['interval_days'] as int?,
      );
      byKey[item.key] = item;
    }

    for (final r in rules.where((r) => r['mode'] == 'pulse')) {
      final activity = r['activity'].toString();
      for (final combo in await _pulseCombos(activity)) {
        final plotId = combo[0] as int;
        if (!plots.containsKey(plotId)) continue;
        final chem = combo[1] as String;
        final key = '$activity|$plotId|${chem.toLowerCase()}';
        if (byKey.containsKey(key)) continue;
        final item = await _build(
          mode: 'pulse',
          activity: activity,
          plotId: plotId,
          plotTitle: plots[plotId]!,
          chemical: chem,
        );
        // FarmPulse stays quiet unless it found a real pattern.
        if (item.status == 'learning') continue;
        byKey[item.key] = item;
      }
    }
    return byKey.values.toList();
  }

  // ---------------------------------------------------------------
  // Snooze / dismiss (only hides the reminder; records are untouched)
  // ---------------------------------------------------------------

  static String _lastIso(ReminderItem it) =>
      it.last == null ? '' : it.last!.toIso8601String().substring(0, 10);

  static Future<bool> isSuppressed(ReminderItem it) async {
    final dismissed = await _get('rem_dismiss_${it.key}');
    if (dismissed != null && dismissed == _lastIso(it)) return true;
    final snooze = await _get('rem_snooze_${it.key}');
    final until = snooze == null ? null : DateTime.tryParse(snooze);
    return until != null && until.isAfter(DateTime.now());
  }

  static Future<void> dismiss(ReminderItem it) async {
    await _set('rem_dismiss_${it.key}', _lastIso(it));
  }

  static Future<void> snooze(ReminderItem it, {int days = 1}) async {
    final now = DateTime.now();
    final until = DateTime(now.year, now.month, now.day + days, 8, 0);
    await _set('rem_snooze_${it.key}', until.toIso8601String());
  }

  // ---------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------

  static bool _refreshing = false;

  /// Re-evaluates all reminders and (re)schedules notifications. Cheap enough
  /// to run whenever Home loads. Never creates farm records.
  static Future<List<ReminderItem>> refresh() async {
    if (_refreshing) return const [];
    _refreshing = true;
    try {
      final items = await evaluate();

      final prev = await _get('magic_sched_ids');
      if (prev != null && prev.isNotEmpty) {
        for (final s in prev.split(',')) {
          final id = int.tryParse(s);
          if (id != null) await NotificationService.instance.cancel(id);
        }
      }

      final scheduled = <int>[];
      final candidates = <MapEntry<DateTime, ReminderItem>>[];
      for (final it in items) {
        if (it.dueAt == null) continue;
        if (it.status == 'watching') {
          candidates.add(MapEntry(it.dueAt!, it));
        } else if (it.status == 'due') {
          final snooze = await _get('rem_snooze_${it.key}');
          final until = snooze == null ? null : DateTime.tryParse(snooze);
          if (until != null && until.isAfter(DateTime.now())) {
            candidates.add(MapEntry(until, it));
          }
        }
      }
      candidates.sort((a, b) => a.key.compareTo(b.key));
      for (final c in candidates.take(30)) {
        final it = c.value;
        final id = 200000 + (_stableHash(it.key) % 90000);
        await NotificationService.instance.schedule(
          id: id,
          title: '${magicActivityLabel(it.activity)} reminder',
          body: reminderBody(it),
          when: c.key,
          payload: 'magic',
        );
        scheduled.add(id);
      }
      await _set('magic_sched_ids', scheduled.join(','));
      return items;
    } catch (e) {
      debugPrint('Magic refresh failed: $e');
      return const [];
    } finally {
      _refreshing = false;
    }
  }
}
