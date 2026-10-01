import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'tasks_data.dart';

/// Free Google Drive backup using the hidden per-app "appDataFolder".
///
/// The local database stays the primary database. Drive only stores backup
/// copies (the last few are kept). Nothing here overwrites local data:
/// restore merges into what is already on the phone.
class CloudBackup {
  CloudBackup._();
  static final CloudBackup instance = CloudBackup._();

  static const String _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const int keepCount = 3;

  final GoogleSignIn _signIn = GoogleSignIn(scopes: [_scope]);
  bool _running = false;

  GoogleSignInAccount? get account => _signIn.currentUser;

  // ---------------------------------------------------------------
  // Settings in app_settings
  // ---------------------------------------------------------------

  Future<String?> _get(String key) async {
    final db = await AppDatabase.instance.database;
    final rows =
        await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  Future<void> _set(String key, String value) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> autoEnabled() async => (await _get('cloud_auto')) == '1';
  Future<void> setAutoEnabled(bool v) => _set('cloud_auto', v ? '1' : '0');
  Future<String?> accountEmail() => _get('cloud_account');
  Future<DateTime?> lastSuccess() async {
    final v = await _get('cloud_last_ok');
    return v == null ? null : DateTime.tryParse(v);
  }

  Future<String?> lastError() => _get('cloud_last_err');

  // ---------------------------------------------------------------
  // Sign in / out
  // ---------------------------------------------------------------

  Future<GoogleSignInAccount?> signIn() async {
    final acct = await _signIn.signIn();
    if (acct != null) {
      await _set('cloud_account', acct.email);
    }
    return acct;
  }

  Future<GoogleSignInAccount?> _silent() async {
    return _signIn.currentUser ?? await _signIn.signInSilently();
  }

  Future<void> signOut() async {
    try {
      await _signIn.signOut();
    } catch (_) {}
    await _set('cloud_account', '');
    await _set('cloud_auto', '0');
  }

  // ---------------------------------------------------------------
  // Payload
  // ---------------------------------------------------------------

  Future<Map<String, dynamic>> _buildPayload() async {
    final db = await AppDatabase.instance.database;
    final payload = await AppDatabase.instance.exportHistory();
    Future<List<Map<String, dynamic>>> all(String table) async {
      final rows = await db.query(table);
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    }

    payload['app'] = 'FarmBook';
    payload['backup_kind'] = 'cloud';
    payload['db_version'] = 7;
    payload['chemicals'] = await all('chemicals');
    final plotRows = await db.query('plots');
    final plotRefs = <int, Map<String, String>>{
      for (final p in plotRows)
        p['id'] as int: {
          'title': p['title'].toString(),
          'plot_name': p['plot_name'].toString(),
          'crop_variety': p['crop_variety'].toString(),
        },
    };
    List<Map<String, dynamic>> withRefs(List<Map<String, dynamic>> rows) {
      for (final r in rows) {
        final pid = r['plot_id'];
        if (pid is int && plotRefs.containsKey(pid)) {
          r['plot_ref'] = plotRefs[pid];
        }
      }
      return rows;
    }

    payload['tasks'] = withRefs(await all('tasks'));
    payload['chemical_stock'] = await all('chemical_stock');
    payload['stock_movements'] = await all('stock_movements');
    payload['reminder_rules'] = withRefs(await all('reminder_rules'));
    return payload;
  }

  Future<int?> _findPlot(dynamic ref) async {
    if (ref is! Map) return null;
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'plots',
      columns: ['id'],
      where: 'title = ? AND plot_name = ? AND crop_variety = ?',
      whereArgs: [
        ref['title']?.toString() ?? '',
        ref['plot_name']?.toString() ?? '',
        ref['crop_variety']?.toString() ?? '',
      ],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  // ---------------------------------------------------------------
  // Drive REST helpers
  // ---------------------------------------------------------------

  Future<Map<String, String>> _headers(GoogleSignInAccount acct) async {
    return acct.authHeaders;
  }

  Future<List<Map<String, dynamic>>> listBackups() async {
    final acct = await _silent();
    if (acct == null) throw StateError('Not signed in to Google.');
    final uri = Uri.parse(
      'https://www.googleapis.com/drive/v3/files'
      '?spaces=appDataFolder&orderBy=createdTime%20desc&pageSize=30'
      '&fields=files(id,name,createdTime,size)',
    );
    final res = await http.get(uri, headers: await _headers(acct));
    if (res.statusCode != 200) {
      throw StateError('Drive list failed (${res.statusCode}).');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final files = (data['files'] as List?) ?? const [];
    return files.map((f) => Map<String, dynamic>.from(f as Map)).toList();
  }

  Future<void> _upload(GoogleSignInAccount acct, String name, String body) async {
    const boundary = 'farmbook_boundary_7d3f';
    final metadata = jsonEncode({
      'name': name,
      'parents': ['appDataFolder'],
    });
    final full = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json\r\n\r\n'
        '$body\r\n'
        '--$boundary--';
    final headers = await _headers(acct);
    final request = http.Request(
      'POST',
      Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
      ),
    );
    request.headers.addAll(headers);
    request.headers['Content-Type'] = 'multipart/related; boundary=$boundary';
    request.bodyBytes = utf8.encode(full);
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      throw StateError('Drive upload failed (${res.statusCode}).');
    }
  }

  Future<void> _trim(GoogleSignInAccount acct) async {
    final files = await listBackups();
    if (files.length <= keepCount) return;
    final headers = await _headers(acct);
    for (final f in files.skip(keepCount)) {
      await http.delete(
        Uri.parse('https://www.googleapis.com/drive/v3/files/${f['id']}'),
        headers: headers,
      );
    }
  }

  // ---------------------------------------------------------------
  // Public actions
  // ---------------------------------------------------------------

  /// Uploads a new backup. Returns null on success or an error message.
  Future<String?> backupNow({bool interactive = false}) async {
    if (_running) return 'A backup is already running.';
    _running = true;
    try {
      var acct = await _silent();
      if (acct == null && interactive) acct = await signIn();
      if (acct == null) {
        await _set('cloud_last_err', 'Not signed in to Google.');
        return 'Not signed in to Google.';
      }
      final payload = await _buildPayload();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      await _upload(acct, 'FarmBook_backup_$stamp.json', jsonEncode(payload));
      await _trim(acct);
      await _set('cloud_last_ok', DateTime.now().toIso8601String());
      await _set('cloud_last_err', '');
      return null;
    } catch (e) {
      debugPrint('Cloud backup failed: $e');
      await _set('cloud_last_err', e.toString());
      return e.toString();
    } finally {
      _running = false;
    }
  }

  /// Runs a silent backup at most once every 24 hours when enabled.
  Future<void> autoBackupIfDue() async {
    try {
      if (!await autoEnabled()) return;
      final last = await lastSuccess();
      if (last != null &&
          DateTime.now().difference(last) < const Duration(hours: 24)) {
        return;
      }
      await backupNow();
    } catch (e) {
      debugPrint('Auto backup skipped: $e');
    }
  }

  /// Downloads one backup and merges it into the local database. A fresh
  /// backup of the current data is uploaded first as a safety copy.
  Future<String> restore(String fileId) async {
    final acct = await _silent();
    if (acct == null) throw StateError('Not signed in to Google.');

    // Safety copy of what is on the phone right now (best effort).
    await backupNow();

    final res = await http.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media'),
      headers: await _headers(acct),
    );
    if (res.statusCode != 200) {
      throw StateError('Drive download failed (${res.statusCode}).');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['app'] != 'FarmBook') {
      throw const FormatException('This is not a FarmBook cloud backup.');
    }
    return _mergeInto(decoded);
  }

  Future<String> _mergeInto(Map<String, dynamic> payload) async {
    final db = await AppDatabase.instance.database;

    // 1) Chemicals first, so restored records re-link to them by name.
    var chemicalsAdded = 0;
    final chems = payload['chemicals'];
    if (chems is List) {
      for (final c in chems) {
        if (c is! Map) continue;
        final name = c['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final exists = await db.query(
          'chemicals',
          columns: ['id'],
          where: 'name = ? COLLATE NOCASE',
          whereArgs: [name],
          limit: 1,
        );
        if (exists.isNotEmpty) continue;
        await db.insert('chemicals', {
          'name': name,
          'price': (c['price'] as num?)?.toDouble() ?? 0,
          'unit': c['unit']?.toString() ?? '',
        });
        chemicalsAdded++;
      }
    }

    // 2) Plots and all farm records (existing duplicate-safe restore).
    final counts = await AppDatabase.instance.restoreHistory(payload);

    // 3) Stock tracking, without duplicating anything already present.
    var stockAdded = 0;
    final stock = payload['chemical_stock'];
    if (stock is List) {
      for (final s in stock) {
        if (s is! Map) continue;
        final name = s['chemical_name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final exists = await db.query(
          'chemical_stock',
          columns: ['id'],
          where: 'chemical_name = ? COLLATE NOCASE',
          whereArgs: [name],
          limit: 1,
        );
        if (exists.isNotEmpty) continue;
        await db.insert('chemical_stock', {
          'chemical_name': name,
          'unit': s['unit']?.toString() ?? '',
          'min_qty': (s['min_qty'] as num?)?.toDouble() ?? 0,
          'started_at':
              s['started_at']?.toString() ?? DateTime.now().toIso8601String(),
        });
        // Only bring movements for stock items that were just added.
        var usedBefore = 0.0;
        final movements = payload['stock_movements'];
        if (movements is List) {
          for (final m in movements) {
            if (m is! Map) continue;
            if (m['chemical_name']?.toString().toLowerCase() !=
                name.toLowerCase()) {
              continue;
            }
            if (m['kind']?.toString() == 'use') {
              usedBefore += (m['qty'] as num?)?.toDouble() ?? 0;
              continue;
            }
            await db.insert('stock_movements', {
              'chemical_name': name,
              'qty': (m['qty'] as num?)?.toDouble() ?? 0,
              'kind': m['kind']?.toString() ?? 'adjust',
              'ref_type': null,
              'ref_id': null,
              'moved_at': m['moved_at']?.toString() ??
                  DateTime.now().toIso8601String(),
              'note': m['note']?.toString() ?? '',
              'created_at': DateTime.now().toIso8601String(),
            });
          }
        }
        if (usedBefore != 0) {
          await db.insert('stock_movements', {
            'chemical_name': name,
            'qty': usedBefore,
            'kind': 'adjust',
            'ref_type': null,
            'ref_id': null,
            'moved_at': DateTime.now().toIso8601String(),
            'note': 'Usage before restore',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
        stockAdded++;
      }
    }

    // 4) Tasks and reminder settings, matched to plots by name.
    final tasks = payload['tasks'];
    if (tasks is List) {
      for (final t in tasks) {
        if (t is! Map) continue;
        final title = t['title']?.toString() ?? '';
        final due = t['due_at']?.toString() ?? '';
        if (title.isEmpty || due.isEmpty) continue;
        final plotId = t['plot_ref'] == null ? null : await _findPlot(t['plot_ref']);
        final dup = await db.query(
          'tasks',
          columns: ['id'],
          where: 'title = ? AND due_at = ?',
          whereArgs: [title, due],
          limit: 1,
        );
        if (dup.isNotEmpty) continue;
        await db.insert('tasks', {
          'plot_id': plotId,
          'title': title,
          'task_type': t['task_type']?.toString() ?? 'Other',
          'due_at': due,
          'remind': (t['remind'] as num?)?.toInt() ?? 1,
          'note': t['note']?.toString() ?? '',
          'done': (t['done'] as num?)?.toInt() ?? 0,
          'created_at':
              t['created_at']?.toString() ?? DateTime.now().toIso8601String(),
        });
      }
    }
    final rules = payload['reminder_rules'];
    if (rules is List) {
      for (final r in rules) {
        if (r is! Map) continue;
        final mode = r['mode']?.toString() ?? '';
        final activity = r['activity']?.toString() ?? '';
        if (mode.isEmpty || activity.isEmpty) continue;
        final plotId = r['plot_ref'] == null ? null : await _findPlot(r['plot_ref']);
        if (mode == 'pattern' && plotId == null) continue;
        final chem = r['chemical_name']?.toString() ?? '';
        final dup = await db.query(
          'reminder_rules',
          columns: ['id'],
          where: plotId == null
              ? 'mode = ? AND activity = ? AND plot_id IS NULL AND chemical_name = ?'
              : 'mode = ? AND activity = ? AND plot_id = ? AND chemical_name = ?',
          whereArgs: plotId == null
              ? [mode, activity, chem]
              : [mode, activity, plotId, chem],
          limit: 1,
        );
        if (dup.isNotEmpty) continue;
        await db.insert('reminder_rules', {
          'mode': mode,
          'activity': activity,
          'plot_id': plotId,
          'chemical_name': chem,
          'enabled': (r['enabled'] as num?)?.toInt() ?? 1,
          'created_at':
              r['created_at']?.toString() ?? DateTime.now().toIso8601String(),
        });
      }
    }
    await TaskStore.rescheduleAll();

    return 'Restored: ${counts['plots_added'] ?? 0} plots, '
        '${counts['sprays_added'] ?? 0} sprays, '
        '${counts['drips_added'] ?? 0} drips, '
        '$chemicalsAdded chemicals'
        '${stockAdded == 0 ? '' : ', $stockAdded stock items'}.';
  }
}
