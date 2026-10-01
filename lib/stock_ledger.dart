import 'package:sqflite/sqflite.dart';

/// One chemical quantity used by a spray or drip record, expressed in the
/// chemical's own unit (ml, l, gram, kg).
class StockUse {
  const StockUse(this.name, this.qty);
  final String name;
  final double qty;
}

/// Low-level stock bookkeeping used inside the existing spray/drip
/// transactions. Stock is only ever reduced for chemicals that the user has
/// switched stock tracking on for, and never for records that were created
/// before tracking started.
class StockLedger {
  static Future<void> syncUse(
    DatabaseExecutor db, {
    required String refType,
    required int refId,
    required DateTime date,
    required List<StockUse> uses,
  }) async {
    final table = refType == 'spray' ? 'sprays' : 'drip_applications';
    final rec = await db.query(
      table,
      columns: ['created_at'],
      where: 'id = ?',
      whereArgs: [refId],
      limit: 1,
    );
    final createdAt = rec.isEmpty
        ? DateTime.now()
        : (DateTime.tryParse(rec.first['created_at'].toString()) ??
            DateTime.now());

    final old = await db.query(
      'stock_movements',
      where: 'ref_type = ? AND ref_id = ?',
      whereArgs: [refType, refId],
    );
    final hadNames =
        old.map((r) => r['chemical_name'].toString().toLowerCase()).toSet();

    await db.delete(
      'stock_movements',
      where: 'ref_type = ? AND ref_id = ?',
      whereArgs: [refType, refId],
    );

    for (final use in uses) {
      if (use.qty <= 0 || use.name.trim().isEmpty) continue;
      final rows = await db.query(
        'chemical_stock',
        where: 'chemical_name = ? COLLATE NOCASE',
        whereArgs: [use.name.trim()],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final started = DateTime.tryParse(rows.first['started_at'].toString());
      final hadBefore = hadNames.contains(use.name.trim().toLowerCase());
      if (!hadBefore && started != null && createdAt.isBefore(started)) {
        // Old record from before stock tracking began: never consume it.
        continue;
      }
      await db.insert('stock_movements', {
        'chemical_name': use.name.trim(),
        'qty': -use.qty,
        'kind': 'use',
        'ref_type': refType,
        'ref_id': refId,
        'moved_at': date.toIso8601String(),
        'note': '',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  static Future<void> removeUse(
    DatabaseExecutor db,
    String refType,
    int refId,
  ) async {
    await db.delete(
      'stock_movements',
      where: 'ref_type = ? AND ref_id = ?',
      whereArgs: [refType, refId],
    );
  }
}
