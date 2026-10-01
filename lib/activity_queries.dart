import 'database.dart';

/// Read-only helpers for the Home "Recent Activities" section.
extension RecentlyActivePlots on AppDatabase {
  /// Plots ordered by their most recent farm activity (spray, drip, labour,
  /// expense or earning), newest first. Each plot appears once. Plots that
  /// have no activity yet come last, newest-created first.
  Future<List<Map<String, dynamic>>> getPlotsByRecentActivity() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.*, MAX(a.d) AS last_activity, MAX(a.c) AS last_created
      FROM plots p
      LEFT JOIN (
        SELECT plot_id, spray_date AS d, created_at AS c FROM sprays
        UNION ALL
        SELECT plot_id, drip_date AS d, created_at AS c FROM drip_applications
        UNION ALL
        SELECT plot_id, labour_date AS d, created_at AS c FROM labour_records
        UNION ALL
        SELECT plot_id, expense_date AS d, created_at AS c FROM other_expenses
        UNION ALL
        SELECT plot_id, earning_date AS d, created_at AS c FROM earnings
      ) a ON a.plot_id = p.id
      GROUP BY p.id
      ORDER BY (MAX(a.d) IS NULL) ASC, MAX(a.d) DESC, MAX(a.c) DESC, p.id DESC
    ''');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }
}
