import 'package:flutter/material.dart';

import 'chemical_picker.dart';
import 'database.dart';
import 'magic_engine.dart';
import 'notifications.dart';
import 'pages.dart' show PlotOverviewPage;

String _statusText(String status) {
  switch (status) {
    case 'watching':
      return 'Watching';
    case 'due':
      return 'Possible overdue';
    case 'inactive':
      return 'Quiet — no recent activity';
    default:
      return 'Learning — needs more records';
  }
}

Future<void> _openPlotById(BuildContext context, int plotId) async {
  final db = await AppDatabase.instance.database;
  final rows = await db.query('plots', where: 'id = ?', whereArgs: [plotId]);
  if (rows.isEmpty || !context.mounted) return;
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

/// First screen: the two modes come first, then what is currently enabled.
class MagicReminderPage extends StatefulWidget {
  const MagicReminderPage({super.key});

  @override
  State<MagicReminderPage> createState() => _MagicReminderPageState();
}

class _MagicReminderPageState extends State<MagicReminderPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _rules = [];
  List<ReminderItem> _items = [];
  final Set<String> _hidden = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await MagicEngine.rules();
    final items = await MagicEngine.evaluate();
    _hidden.clear();
    for (final it in items) {
      if (it.status == 'due' && await MagicEngine.isSuppressed(it)) {
        _hidden.add(it.key);
      }
    }
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _items = items;
      _loading = false;
    });
    // Keep scheduled notifications in step with what is enabled.
    MagicEngine.refresh();
  }

  Future<void> _openMode(String mode) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MagicModePage(mode: mode)),
    );
    await _load();
  }

  ReminderItem? _itemFor(Map<String, dynamic> rule) {
    final key =
        '${rule['activity']}|${rule['plot_id']}|${rule['chemical_name'].toString().toLowerCase()}';
    for (final it in _items) {
      if (it.key == key) return it;
    }
    return null;
  }

  Widget _modeCard({
    required IconData icon,
    required String title,
    required String text,
    required String mode,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openMode(mode),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFE3F2FD),
                child: Icon(icon, color: const Color(0xFF0D47A1)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(text, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final due = _items
        .where((i) => i.status == 'due' && !_hidden.contains(i.key))
        .toList();
    final enabled = _rules.where((r) => (r['enabled'] as int) == 1).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Magic Reminder')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  const Text(
                    'Reminders come only from your own farm records and are '
                    'just a nudge to check. FarmBook never records anything '
                    'for you.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  _modeCard(
                    icon: Icons.timeline,
                    title: 'Pattern Reminder',
                    text: 'FarmBook learns the timing pattern from the '
                        'records you choose to monitor.',
                    mode: 'pattern',
                  ),
                  _modeCard(
                    icon: Icons.insights,
                    title: 'FarmPulse',
                    text: 'FarmBook analyzes your farm records and detects '
                        'meaningful activity patterns that may need checking.',
                    mode: 'pulse',
                  ),
                  if (due.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(2, 14, 2, 6),
                      child: Text(
                        'Worth a look',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    for (final it in due) _dueCard(it),
                  ],
                  const Padding(
                    padding: EdgeInsets.fromLTRB(2, 14, 2, 6),
                    child: Text(
                      'Enabled',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  if (enabled.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Nothing enabled yet. Choose a mode above.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  for (final mode in const ['pattern', 'pulse']) ...[
                    if (enabled.any((r) => r['mode'] == mode)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
                        child: Text(
                          mode == 'pattern' ? 'Pattern Reminder' : 'FarmPulse',
                          style: const TextStyle(color: Color(0xFF0D47A1)),
                        ),
                      ),
                      for (final r in enabled.where((r) => r['mode'] == mode))
                        _ruleTile(r),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _dueCard(ReminderItem it) {
    return Card(
      color: const Color(0xFFFFF8E1),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${magicActivityLabel(it.activity)} reminder',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(reminderBody(it, includeDaysSince: true)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _openPlotById(context, it.plotId),
                  child: const Text('View Plot'),
                ),
                TextButton(
                  onPressed: () async {
                    await MagicEngine.snooze(it);
                    await _load();
                  },
                  child: const Text('Snooze'),
                ),
                TextButton(
                  onPressed: () async {
                    await MagicEngine.dismiss(it);
                    await _load();
                  },
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ruleTile(Map<String, dynamic> r) {
    final activity = r['activity'].toString();
    if (r['mode'] == 'pulse') {
      final count = _items
          .where((i) => i.mode == 'pulse' && i.activity == activity)
          .length;
      return Card(
        child: ListTile(
          title: Text(magicActivityLabel(activity)),
          subtitle: Text(
            'All relevant plots\nStatus: ON'
            '${count == 0 ? '' : ' • $count pattern${count == 1 ? '' : 's'} found'}',
          ),
          isThreeLine: true,
        ),
      );
    }
    final item = _itemFor(r);
    final chem = r['chemical_name'].toString();
    return Card(
      child: ListTile(
        title: Text(magicActivityLabel(activity)),
        subtitle: Text(
          '${r['plot_title'] ?? ''}'
          '${chem.isEmpty ? '' : '\n$chem'}'
          '${item?.intervalDays == null ? '' : (item!.manual ? '\nEvery ${item.intervalDays} days (set by you)' : '\nApprox. interval: ${item.intervalDays} days')}'
          '\nStatus: ${_statusText(item?.status ?? 'learning')}',
        ),
        isThreeLine: true,
      ),
    );
  }
}

/// Second screen: which activities to enable for the chosen mode.
class MagicModePage extends StatefulWidget {
  const MagicModePage({super.key, required this.mode});

  final String mode; // 'pattern' | 'pulse'

  @override
  State<MagicModePage> createState() => _MagicModePageState();
}

class _MagicModePageState extends State<MagicModePage> {
  bool _loading = true;
  List<Map<String, dynamic>> _rules = [];

  bool get _isPattern => widget.mode == 'pattern';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await MagicEngine.rules();
    if (!mounted) return;
    setState(() {
      _rules = all.where((r) => r['mode'] == widget.mode).toList();
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _rulesFor(String activity) =>
      _rules.where((r) => r['activity'] == activity).toList();

  bool _activityOn(String activity) =>
      _rulesFor(activity).any((r) => (r['enabled'] as int) == 1);

  Future<void> _toggle(String activity, bool on) async {
    if (on) {
      await NotificationService.instance.requestPermission();
    }
    if (_isPattern) {
      final existing = _rulesFor(activity);
      if (on && existing.isEmpty) {
        final added = await _configure(activity);
        if (!added) return;
      } else {
        await MagicEngine.setPatternActivityEnabled(activity, on);
      }
    } else {
      await MagicEngine.setPulse(activity, on);
    }
    await _load();
    MagicEngine.refresh();
  }

  /// Pattern Reminder setup: pick the plot (and chemical for Spray).
  Future<bool> _configure(String activity) async {
    final db = await AppDatabase.instance.database;
    final plots = await AppDatabase.instance.getPlots();
    if (!mounted) return false;
    if (plots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a crop / plot first.')),
      );
      return false;
    }
    final chemRows = activity == 'spray'
        ? await db.query('chemicals', orderBy: 'name COLLATE NOCASE ASC')
        : <Map<String, Object?>>[];
    if (!mounted) return false;
    if (activity == 'spray' && chemRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add chemicals in the Chemicals tab first.'),
        ),
      );
      return false;
    }
    int plotId = plots.first['id'] as int;
    String chem = chemRows.isEmpty ? '' : chemRows.first['name'].toString();
    bool fixedFrequency = false;
    final daysCtrl = TextEditingController(text: '7');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${magicActivityLabel(activity)} — Pattern Reminder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: plotId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Select plot'),
                items: [
                  for (final p in plots)
                    DropdownMenuItem(
                      value: p['id'] as int,
                      child: Text(p['title'].toString()),
                    ),
                ],
                onChanged: (v) => setLocal(() => plotId = v ?? plotId),
              ),
              if (activity == 'spray') ...[
                const SizedBox(height: 12),
                PickerField(
                  label: 'Select chemical',
                  value: chem,
                  onTap: () async {
                    final name = await pickFromList(
                      ctx,
                      title: 'Choose chemical',
                      items: [for (final c in chemRows) c['name'].toString()],
                      selected: chem,
                    );
                    if (name != null) setLocal(() => chem = name);
                  },
                ),
              ],
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Learn')),
                  ButtonSegment(value: true, label: Text('Set frequency')),
                ],
                selected: {fixedFrequency},
                onSelectionChanged: (v) =>
                    setLocal(() => fixedFrequency = v.first),
              ),
              const SizedBox(height: 10),
              if (fixedFrequency)
                TextField(
                  controller: daysCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Repeat every (days)',
                    helperText: 'Counted from the last matching record.',
                  ),
                )
              else
                const Text(
                  'FarmBook learns the timing from your past records. It '
                  'needs at least two matching gaps before it can notice a '
                  'pattern.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enable'),
            ),
          ],
        ),
      ),
    );
    final days = int.tryParse(daysCtrl.text.trim());
    daysCtrl.dispose();
    if (ok != true) return false;
    if (fixedFrequency && (days == null || days < 1 || days > 365)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a frequency between 1 and 365 days.')),
        );
      }
      return false;
    }
    await MagicEngine.addPatternRule(
      activity: activity,
      plotId: plotId,
      chemical: activity == 'spray' ? chem : '',
      intervalDays: fixedFrequency ? days : null,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isPattern ? 'Pattern Reminder' : 'FarmPulse'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Text(
                  _isPattern
                      ? 'Which activities do you want to enable?'
                      : 'Which activities do you want FarmPulse to monitor?',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                for (final a in kMagicActivities) _activityCard(a),
              ],
            ),
    );
  }

  Widget _activityCard(String activity) {
    final on = _activityOn(activity);
    final rules = _rulesFor(activity);
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: Text(magicActivityLabel(activity)),
            value: on,
            onChanged: (v) => _toggle(activity, v),
          ),
          if (_isPattern && rules.isNotEmpty) ...[
            for (final r in rules)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.fromLTRB(28, 0, 8, 0),
                title: Text(
                  '${r['plot_title'] ?? ''}'
                  '${r['chemical_name'].toString().isEmpty ? '' : ' • ${r['chemical_name']}'}'
                  '${r['interval_days'] == null ? '' : ' • every ${r['interval_days']} d'}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: (r['enabled'] as int) == 1,
                      onChanged: (v) async {
                        await MagicEngine.setRuleEnabled(r['id'] as int, v);
                        await _load();
                        MagicEngine.refresh();
                      },
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await MagicEngine.deleteRule(r['id'] as int);
                        await _load();
                        MagicEngine.refresh();
                      },
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 6),
                child: TextButton.icon(
                  onPressed: () async {
                    final added = await _configure(activity);
                    if (added) {
                      await _load();
                      MagicEngine.refresh();
                    }
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add plot'),
                ),
              ),
            ),
          ],
          if (!_isPattern && on)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Watches all relevant plots and only speaks up when your '
                  'records show a clear pattern.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
