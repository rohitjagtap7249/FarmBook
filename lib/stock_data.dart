import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'notifications.dart';

/// Unit helpers for chemicals measured in ml / l / gram / kg.
class StockUnits {
  static const Map<String, double> _mass = {'gram': 1, 'kg': 1000};
  static const Map<String, double> _volume = {'ml': 1, 'l': 1000};

  static String norm(String unit) => unit.trim().toLowerCase();

  /// Units the user may type a quantity in for a chemical stocked in [unit].
  static List<String> options(String unit) {
    final u = norm(unit);
    if (_mass.containsKey(u)) return ['kg', 'gram'];
    if (_volume.containsKey(u)) return ['l', 'ml'];
    return [u.isEmpty ? 'unit' : u];
  }

  /// Converts [qty] typed in [fromUnit] into the stock unit [stockUnit].
  static double convert(double qty, String fromUnit, String stockUnit) {
    final f = norm(fromUnit);
    final s = norm(stockUnit);
    if (_mass.containsKey(f) && _mass.containsKey(s)) {
      return qty * _mass[f]! / _mass[s]!;
    }
    if (_volume.containsKey(f) && _volume.containsKey(s)) {
      return qty * _volume[f]! / _volume[s]!;
    }
    return qty;
  }

  /// Friendly text, e.g. 2250 gram -> "2.25 kg".
  static String format(double qty, String unit) {
    final u = norm(unit);
    var v = qty;
    var label = u;
    if (u == 'gram' && v.abs() >= 1000) {
      v = v / 1000;
      label = 'kg';
    } else if (u == 'ml' && v.abs() >= 1000) {
      v = v / 1000;
      label = 'l';
    } else if (u == 'gram') {
      label = 'g';
    }
    final txt = v == v.roundToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(v.abs() < 10 ? 2 : 1);
    return label.isEmpty ? txt : '$txt $label';
  }
}

/// Optional chemical stock tracking. Tracking starts only when the user
/// switches it on for a chemical; old spray records are never consumed.
class StockStore {
  StockStore._();

  static Future<List<Map<String, dynamic>>> items() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT s.id, s.chemical_name, s.unit, s.min_qty, s.started_at,
        COALESCE((SELECT SUM(m.qty) FROM stock_movements m
                  WHERE m.chemical_name = s.chemical_name COLLATE NOCASE), 0)
          AS balance,
        COALESCE((SELECT c.price FROM chemicals c
                  WHERE c.name = s.chemical_name COLLATE NOCASE LIMIT 1), 0)
          AS price
      FROM chemical_stock s
      ORDER BY s.chemical_name COLLATE NOCASE ASC
    ''');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Chemicals that exist in the chemical database but are not tracked yet.
  static Future<List<Map<String, dynamic>>> untrackedChemicals() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.name, c.unit, c.price FROM chemicals c
      WHERE NOT EXISTS (
        SELECT 1 FROM chemical_stock s
        WHERE s.chemical_name = c.name COLLATE NOCASE)
      ORDER BY c.name COLLATE NOCASE ASC
    ''');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  static Future<void> startTracking({
    required String name,
    required String unit,
    required double openingQty,
    required double minQty,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert(
        'chemical_stock',
        {
          'chemical_name': name.trim(),
          'unit': unit.trim(),
          'min_qty': minQty,
          'started_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (openingQty != 0) {
        await txn.insert('stock_movements', {
          'chemical_name': name.trim(),
          'qty': openingQty,
          'kind': 'opening',
          'ref_type': null,
          'ref_id': null,
          'moved_at': now,
          'note': 'Opening stock',
          'created_at': now,
        });
      }
    });
  }

  static Future<void> addPurchase({
    required String name,
    required double qty,
    required DateTime date,
    String note = '',
  }) async {
    final db = await AppDatabase.instance.database;
    await db.insert('stock_movements', {
      'chemical_name': name.trim(),
      'qty': qty,
      'kind': 'purchase',
      'ref_type': null,
      'ref_id': null,
      'moved_at': date.toIso8601String(),
      'note': note.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Sets the balance to [actualQty] by recording the difference.
  static Future<void> correctBalance({
    required String name,
    required double actualQty,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(qty), 0) AS b FROM stock_movements '
      'WHERE chemical_name = ? COLLATE NOCASE',
      [name.trim()],
    );
    final current = (rows.first['b'] as num).toDouble();
    final diff = actualQty - current;
    if (diff.abs() < 0.0000001) return;
    await db.insert('stock_movements', {
      'chemical_name': name.trim(),
      'qty': diff,
      'kind': 'adjust',
      'ref_type': null,
      'ref_id': null,
      'moved_at': DateTime.now().toIso8601String(),
      'note': 'Stock correction',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> setMinQty(String name, double minQty) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'chemical_stock',
      {'min_qty': minQty},
      where: 'chemical_name = ? COLLATE NOCASE',
      whereArgs: [name.trim()],
    );
  }

  static Future<void> stopTracking(String name) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'stock_movements',
        where: 'chemical_name = ? COLLATE NOCASE',
        whereArgs: [name.trim()],
      );
      await txn.delete(
        'chemical_stock',
        where: 'chemical_name = ? COLLATE NOCASE',
        whereArgs: [name.trim()],
      );
    });
  }

  static Future<List<Map<String, dynamic>>> movements(String name) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'stock_movements',
      where: 'chemical_name = ? COLLATE NOCASE',
      whereArgs: [name.trim()],
      orderBy: 'moved_at DESC, id DESC',
      limit: 60,
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Shows a low-stock notification once each time a chemical drops to or
  /// below its minimum level. Purely informational.
  static Future<void> checkLowStock() async {
    try {
      final db = await AppDatabase.instance.database;
      for (final item in await items()) {
        final min = (item['min_qty'] as num).toDouble();
        final name = item['chemical_name'].toString();
        final key = 'stock_low_$name';
        final rows =
            await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
        final alreadyTold = rows.isNotEmpty && rows.first['value'] == '1';
        if (min <= 0) continue;
        final balance = (item['balance'] as num).toDouble();
        final unit = item['unit'].toString();
        if (balance <= min) {
          if (!alreadyTold) {
            await NotificationService.instance.showNow(
              id: 300000 + (name.hashCode & 0xFFFF),
              title: 'Low stock',
              body: '$name is low: ${StockUnits.format(balance, unit)} left '
                  '(minimum ${StockUnits.format(min, unit)}).',
              payload: 'stock',
            );
            await db.insert(
              'app_settings',
              {'key': key, 'value': '1'},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        } else if (alreadyTold) {
          await db.insert(
            'app_settings',
            {'key': key, 'value': '0'},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    } catch (_) {
      // Low-stock alerts are optional; never break the app for them.
    }
  }
}
