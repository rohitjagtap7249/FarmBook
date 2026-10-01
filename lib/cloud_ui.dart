import 'package:flutter/material.dart';

import 'cloud_backup.dart';

String _when(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '${d.day} ${months[d.month - 1]} ${d.year}, $h12:$mm $ap';
}

/// "Online Backup" block shown inside the existing Backup & Restore page.
class OnlineBackupSection extends StatefulWidget {
  const OnlineBackupSection({super.key});

  @override
  State<OnlineBackupSection> createState() => _OnlineBackupSectionState();
}

class _OnlineBackupSectionState extends State<OnlineBackupSection> {
  final CloudBackup _cloud = CloudBackup.instance;
  bool _busy = false;
  bool _loaded = false;
  String _email = '';
  bool _auto = false;
  DateTime? _last;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final email = await _cloud.accountEmail() ?? '';
    final auto = await _cloud.autoEnabled();
    final last = await _cloud.lastSuccess();
    final err = await _cloud.lastError() ?? '';
    if (!mounted) return;
    setState(() {
      _email = email;
      _auto = auto;
      _last = last;
      _error = err;
      _loaded = true;
    });
  }

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      final acct = await _cloud.signIn();
      if (acct == null) {
        _msg('Google sign-in was cancelled.');
      } else {
        await _cloud.setAutoEnabled(true);
        final err = await _cloud.backupNow();
        _msg(err == null ? 'Signed in. First backup done.' : 'Signed in. Backup failed: $err');
      }
    } catch (e) {
      _msg('Google sign-in failed: $e');
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    final err = await _cloud.backupNow(interactive: true);
    _msg(err == null ? 'Backup uploaded to Google Drive.' : 'Backup failed: $err');
    await _refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final files = await _cloud.listBackups();
      if (!mounted) return;
      if (files.isEmpty) {
        _msg('No backups found on Google Drive.');
        return;
      }
      final picked = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Choose a backup'),
          children: [
            for (final f in files)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, f),
                child: Text(
                  _when(
                    (DateTime.tryParse(f['createdTime'].toString()) ??
                            DateTime.now())
                        .toLocal(),
                  ),
                ),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore from Google Drive?'),
          content: const Text(
            'The backup is added to your existing data. Nothing on this phone '
            'is deleted, and exact duplicates are skipped. A fresh backup of '
            'your current data is uploaded first as a safety copy.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (sure != true) return;
      final summary = await _cloud.restore(picked['id'].toString());
      _msg(summary);
    } catch (e) {
      _msg('Restore failed: $e');
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final signedIn = _email.isNotEmpty;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_outlined, color: Color(0xFF0D47A1)),
                SizedBox(width: 10),
                Text(
                  'Online Backup',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Free backup to your own Google Drive (a hidden FarmBook '
              'folder). FarmBook keeps working offline; Drive only holds '
              'backup copies.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (!signedIn)
              FilledButton.icon(
                onPressed: _busy ? null : _signIn,
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google'),
              )
            else ...[
              Text('Google account: $_email'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Automatic backup'),
                subtitle: const Text('About once a day, when you open FarmBook.'),
                value: _auto,
                onChanged: _busy
                    ? null
                    : (v) async {
                        await _cloud.setAutoEnabled(v);
                        await _refresh();
                      },
              ),
              Text(
                _last == null
                    ? 'Last backup: none yet'
                    : 'Last backup: ${_when(_last!)}',
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Last problem: $_error',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _backupNow,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('Backup now'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _restore,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Restore'),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await _cloud.signOut();
                        await _refresh();
                      },
                child: const Text('Sign out'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
