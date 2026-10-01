import 'package:sqflite/sqflite.dart';

/// Extra tables added in database version 7.
/// Everything here is CREATE TABLE IF NOT EXISTS, so it is safe to run
/// on every open and never touches existing FarmBook data.
Future<void> createExtraTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      plot_id INTEGER,
      title TEXT NOT NULL,
      task_type TEXT NOT NULL DEFAULT 'Other',
      due_at TEXT NOT NULL,
      remind INTEGER NOT NULL DEFAULT 1,
      note TEXT NOT NULL DEFAULT '',
      done INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS chemical_stock (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      chemical_name TEXT NOT NULL COLLATE NOCASE,
      unit TEXT NOT NULL DEFAULT '',
      min_qty REAL NOT NULL DEFAULT 0,
      started_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_chemical_stock_name
    ON chemical_stock(chemical_name COLLATE NOCASE)
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS stock_movements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      chemical_name TEXT NOT NULL COLLATE NOCASE,
      qty REAL NOT NULL,
      kind TEXT NOT NULL,
      ref_type TEXT,
      ref_id INTEGER,
      moved_at TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_stock_mov_name ON stock_movements(chemical_name COLLATE NOCASE)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_stock_mov_ref ON stock_movements(ref_type, ref_id)',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS reminder_rules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      mode TEXT NOT NULL,
      activity TEXT NOT NULL,
      plot_id INTEGER,
      chemical_name TEXT NOT NULL DEFAULT '',
      enabled INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL
    )
  ''');
}
