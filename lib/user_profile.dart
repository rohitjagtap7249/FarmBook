import 'package:sqflite/sqflite.dart';

import 'database.dart';

/// The farmer's name, shown in the Home greeting. Stored locally in the
/// existing app_settings table.
class UserProfile {
  UserProfile._();

  static const String _key = 'user_name';

  static Future<String> name() async {
    final db = await AppDatabase.instance.database;
    final rows =
        await db.query('app_settings', where: 'key = ?', whereArgs: [_key]);
    if (rows.isEmpty) return '';
    return rows.first['value']?.toString().trim() ?? '';
  }

  static Future<void> setName(String value) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'app_settings',
      {'key': _key, 'value': value.trim()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
