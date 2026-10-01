import 'package:flutter/material.dart';

import 'database.dart';
import 'notifications.dart';
import 'pages.dart' show PlotOverviewPage;
import 'tasks_data.dart';

const List<String> kTaskTypes = [
  'Spray',
  'Drip',
  'Labour',
  'Other Expenses',
  'Other',
];

String _fmtDue(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '${d.day} ${months[d.month - 1]} ${d.year}, $h12:$mm $ap';
}

/// Task list. Opened from More-style navigation or after saving a task.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _tasks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await TaskStore.all();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  Future<void> _openEditor([Map<String, dynamic>? task]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddTaskPage(task: task)),
    );
    await _load();
  }

  Future<void> _openPlot(Map<String, dynamic> task) async {
    final plotId = task['plot_id'] as int?;
    if (plotId == null) return;
    final db = await AppDatabase.instance.database;
    final rows = await db.query('plots', where: 'id = ?', whereArgs: [plotId]);
    if (rows.isEmpty || !mounted) return;
    final p = rows.first;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlotOverviewPage(
          plotId: plotId,
          plotTitle: p['title'].toString(),
          plotName: p['plot_name'].toString(),
          cropVariety: p['crop_variety'].toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _tasks.where((t) => (t['done'] as int) == 0).toList();
    final done = _tasks.where((t) => (t['done'] as int) == 1).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Task'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              children: [
                const Text(
                  'Tasks are plans only. Completing a task does not create a '
                  'farm record — record the activity yourself when it is done.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (pending.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No pending tasks.')),
                  ),
                for (final t in pending) _tile(t),
                if (done.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
                    child: Text(
                      'Completed',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final t in done) _tile(t),
                ],
              ],
            ),
    );
  }

  Widget _tile(Map<String, dynamic> t) {
    final due = DateTime.tryParse(t['due_at'].toString()) ?? DateTime.now();
    final isDone = (t['done'] as int) == 1;
    final overdue = !isDone && due.isBefore(DateTime.now());
    final plot = (t['plot_title'] ?? '').toString();
    return Card(
      child: ListTile(
        leading: Checkbox(
          value: isDone,
          onChanged: (v) async {
            await TaskStore.setDone(t['id'] as int, v ?? false);
            await _load();
          },
        ),
        title: Text(
          t['title'].toString(),
          style: TextStyle(
            decoration: isDone ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          [
            if (plot.isNotEmpty) plot,
            t['task_type'].toString(),
            _fmtDue(due),
            if (overdue) 'Overdue',
          ].join(' • '),
          style: TextStyle(color: overdue ? Colors.red.shade700 : null),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              await _openEditor(t);
            } else if (v == 'plot') {
              await _openPlot(t);
            } else if (v == 'snooze') {
              await TaskStore.snooze(t['id'] as int, const Duration(days: 1));
              await _load();
            } else if (v == 'delete') {
              await TaskStore.delete(t['id'] as int);
              await _load();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if ((t['plot_id'] as int?) != null)
              const PopupMenuItem(value: 'plot', child: Text('Open plot')),
            if (!isDone)
              const PopupMenuItem(value: 'snooze', child: Text('Snooze 1 day')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => _openEditor(t),
      ),
    );
  }
}

/// Add / edit a task. When opened from a crop, [initialPlotId] is preselected.
class AddTaskPage extends StatefulWidget {
  const AddTaskPage({super.key, this.initialPlotId, this.task});

  final int? initialPlotId;
  final Map<String, dynamic>? task;

  @override
  State<AddTaskPage> createState() => _AddTaskPageState();
}

class _AddTaskPageState extends State<AddTaskPage> {
  final _titleCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  List<Map<String, dynamic>> _plots = [];
  int? _plotId;
  String _type = 'Spray';
  DateTime _due = DateTime.now().add(const Duration(days: 1));
  bool _remind = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _due = DateTime(_due.year, _due.month, _due.day, 7, 0);
    _init();
  }

  Future<void> _init() async {
    final plots = await AppDatabase.instance.getPlots();
    final t = widget.task;
    if (t != null) {
      _titleCtrl.text = t['title'].toString();
      _noteCtrl.text = t['note'].toString();
      _plotId = t['plot_id'] as int?;
      _type = kTaskTypes.contains(t['task_type'].toString())
          ? t['task_type'].toString()
          : 'Other';
      _due = DateTime.tryParse(t['due_at'].toString()) ?? _due;
      _remind = (t['remind'] as int) == 1;
    } else {
      _plotId = widget.initialPlotId;
    }
    if (!mounted) return;
    setState(() {
      _plots = plots;
      if (_plotId != null && !plots.any((p) => p['id'] == _plotId)) {
        _plotId = null;
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (d == null) return;
    setState(() {
      _due = DateTime(d.year, d.month, d.day, _due.hour, _due.minute);
    });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _due.hour, minute: _due.minute),
    );
    if (t == null) return;
    setState(() {
      _due = DateTime(_due.year, _due.month, _due.day, t.hour, t.minute);
    });
  }

  Future<void> _save() async {
    var title = _titleCtrl.text.trim();
    if (title.isEmpty) title = _type;
    setState(() => _saving = true);
    try {
      if (_remind) {
        await NotificationService.instance.requestPermission();
      }
      final t = widget.task;
      if (t == null) {
        await TaskStore.add(
          plotId: _plotId,
          title: title,
          taskType: _type,
          dueAt: _due,
          remind: _remind,
          note: _noteCtrl.text,
        );
      } else {
        await TaskStore.update(
          id: t['id'] as int,
          plotId: _plotId,
          title: title,
          taskType: _type,
          dueAt: _due,
          remind: _remind,
          note: _noteCtrl.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save task: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'Add Task' : 'Edit Task'),
        actions: [
          IconButton(
            tooltip: 'All tasks',
            icon: const Icon(Icons.checklist),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TasksPage()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<int?>(
                  value: _plotId,
                  decoration: const InputDecoration(labelText: 'Crop / plot'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('No specific plot'),
                    ),
                    for (final p in _plots)
                      DropdownMenuItem<int?>(
                        value: p['id'] as int,
                        child: Text(p['title'].toString()),
                      ),
                  ],
                  onChanged: (v) => setState(() => _plotId = v),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(labelText: 'Task type'),
                  items: [
                    for (final t in kTaskTypes)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Task (optional)',
                    hintText: 'e.g. Spray Chemical X',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          '${_due.day}/${_due.month}/${_due.year}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickTime,
                        icon: const Icon(Icons.access_time, size: 18),
                        label: Text(
                          TimeOfDay(hour: _due.hour, minute: _due.minute)
                              .format(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remind me'),
                  subtitle: const Text('Sends a notification at this time.'),
                  value: _remind,
                  onChanged: (v) => setState(() => _remind = v),
                ),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save task'),
                ),
              ],
            ),
    );
  }
}
