import 'database.dart';
import 'notifications.dart';

/// Data access for the Normal Task Manager. A task is only a future plan:
/// it never becomes a completed farm record on its own.
class TaskStore {
  TaskStore._();

  static Future<List<Map<String, dynamic>>> all() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT t.*, p.title AS plot_title
      FROM tasks t LEFT JOIN plots p ON p.id = t.plot_id
      ORDER BY t.done ASC, t.due_at ASC, t.id ASC
    ''');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  static Future<int> add({
    required int? plotId,
    required String title,
    required String taskType,
    required DateTime dueAt,
    required bool remind,
    required String note,
  }) async {
    final db = await AppDatabase.instance.database;
    final id = await db.insert('tasks', {
      'plot_id': plotId,
      'title': title.trim(),
      'task_type': taskType,
      'due_at': dueAt.toIso8601String(),
      'remind': remind ? 1 : 0,
      'note': note.trim(),
      'done': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _reschedule(id);
    return id;
  }

  static Future<void> update({
    required int id,
    required int? plotId,
    required String title,
    required String taskType,
    required DateTime dueAt,
    required bool remind,
    required String note,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'tasks',
      {
        'plot_id': plotId,
        'title': title.trim(),
        'task_type': taskType,
        'due_at': dueAt.toIso8601String(),
        'remind': remind ? 1 : 0,
        'note': note.trim(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _reschedule(id);
  }

  static Future<void> setDone(int id, bool done) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'tasks',
      {'done': done ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _reschedule(id);
  }

  static Future<void> delete(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
    await NotificationService.instance.cancel(id);
  }

  /// Snoozes a task reminder by moving its due time forward.
  static Future<void> snooze(int id, Duration by) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    var base = DateTime.tryParse(rows.first['due_at'].toString()) ??
        DateTime.now();
    if (base.isBefore(DateTime.now())) base = DateTime.now();
    await db.update(
      'tasks',
      {'due_at': base.add(by).toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _reschedule(id);
  }

  static Future<void> _reschedule(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT t.*, p.title AS plot_title
      FROM tasks t LEFT JOIN plots p ON p.id = t.plot_id
      WHERE t.id = ?
    ''', [id]);
    await NotificationService.instance.cancel(id);
    if (rows.isEmpty) return;
    final t = rows.first;
    if ((t['done'] as int) == 1 || (t['remind'] as int) != 1) return;
    final due = DateTime.tryParse(t['due_at'].toString());
    if (due == null) return;
    final plot = (t['plot_title'] ?? '').toString();
    final title = t['title'].toString();
    await NotificationService.instance.schedule(
      id: id,
      title: 'Task reminder',
      body: plot.isEmpty ? title : '$title — $plot',
      when: due,
      payload: 'task:$id',
    );
  }

  /// Re-schedules every pending task reminder. Safe to call on app start.
  static Future<void> rescheduleAll() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'tasks',
      columns: ['id'],
      where: 'done = 0 AND remind = 1',
    );
    for (final r in rows) {
      await _reschedule(r['id'] as int);
    }
  }
}
