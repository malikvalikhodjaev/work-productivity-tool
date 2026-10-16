import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'domain.dart';

class LocalDatabase {
  final Database db;
  LocalDatabase(String file) : db = sqlite3.open(file) {
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=FULL');
    db.execute('PRAGMA busy_timeout=5000');
    db.execute(
      'CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS snapshots (key TEXT PRIMARY KEY, body TEXT NOT NULL, captured INTEGER NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS outbox (id TEXT PRIMARY KEY, entity TEXT NOT NULL, route TEXT NOT NULL, body TEXT NOT NULL, server_id TEXT, state TEXT NOT NULL DEFAULT \'queued\', error TEXT, attempted INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS drafts (entity TEXT PRIMARY KEY, body TEXT NOT NULL)',
    );
    db.execute('PRAGMA user_version=1');
    if (get('deviceId') == null) set('deviceId', uuid.v4());
  }
  T atomic<T>(T Function() work) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final result = work();
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  dynamic get(String key) {
    final r = db.select('SELECT value FROM kv WHERE key=?', [key]);
    return r.isEmpty ? null : jsonDecode(r.first['value'] as String);
  }

  void set(String key, dynamic value) => db.execute(
    'INSERT INTO kv(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, jsonEncode(value)],
  );
  void remove(String key) => db.execute('DELETE FROM kv WHERE key=?', [key]);
  Json snapshot(String key) {
    final r = db.select('SELECT body FROM snapshots WHERE key=?', [key]);
    return r.isEmpty
        ? <String, dynamic>{}
        : object(jsonDecode(r.first['body'] as String));
  }

  void capture(String key, Json body) => db.execute(
    'INSERT INTO snapshots(key,body,captured) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET body=excluded.body,captured=excluded.captured',
    [key, jsonEncode(body), DateTime.now().millisecondsSinceEpoch],
  );
  List<Json> get queue => db
      .select('SELECT * FROM outbox ORDER BY created,id')
      .map((r) => {...r, 'body': object(jsonDecode(r['body'] as String))})
      .toList();
  List<Json> get drafts => db
      .select('SELECT entity,body FROM drafts')
      .map(
        (r) => {
          'entity': r['entity'],
          'body': object(jsonDecode(r['body'] as String)),
        },
      )
      .toList();
  Json? draft(String entity) {
    final r = db.select('SELECT body FROM drafts WHERE entity=?', [entity]);
    return r.isEmpty ? null : object(jsonDecode(r.first['body'] as String));
  }

  void keepDraft(String entity, Json body) => db.execute(
    'INSERT INTO drafts(entity,body) VALUES(?,?) ON CONFLICT(entity) DO UPDATE SET body=excluded.body',
    [entity, jsonEncode(body)],
  );
  String enqueue(String entity, String route, Json body, {Json? draft}) =>
      atomic(() {
        final previous = queue.where((q) => q['entity'] == entity).toList();
        if (previous.any((q) => q['attempted'] == 1)) {
          throw StateError(
            'Эта правка ожидает подтверждения или разбора. Исходный текст сохранён.',
          );
        }
        if (previous.isNotEmpty) {
          final old = object(previous.first['body']);
          // Coalesce only never-sent edits; preserve the original server version and create operation.
          if (route == '/api/native/command') {
            body = {
              ...body,
              'action': old['module'] == 'inbox' && body['action'] != 'save'
                  ? body['action']
                  : old['action'],
              'expectedUpdatedAt': old['expectedUpdatedAt'],
              if (old.containsKey('expectedTarget'))
                'expectedTarget': old['expectedTarget'],
              'input': {
                ...object(old['input']),
                ...object(body['input']),
                if (object(old['input']).containsKey('clientId'))
                  'clientId': object(old['input'])['clientId'],
                if (object(old['input']).containsKey('id'))
                  'id': object(old['input'])['id'],
              },
            };
            if (object(old['input']).containsKey('clientId')) {
              (body['input'] as Map).remove('id');
            }
            if (object(old['input']).containsKey('expectedRevision')) {
              (body['input'] as Map)['expectedRevision'] = object(
                old['input'],
              )['expectedRevision'];
            }
            if (object(old['input']).containsKey('expectedUpdatedAt')) {
              (body['input'] as Map)['expectedUpdatedAt'] = object(
                old['input'],
              )['expectedUpdatedAt'];
            }
          } else if (route == '/api/writing') {
            body = {...body, 'expectedRevision': old['expectedRevision']};
          }
          db.execute('DELETE FROM outbox WHERE entity=?', [entity]);
        }
        final id = body['requestId']?.toString() ?? uuid.v4();
        db.execute(
          'INSERT INTO outbox(id,entity,route,body,server_id,created) VALUES(?,?,?,?,?,?)',
          [
            id,
            entity,
            route,
            jsonEncode(body),
            get('serverId'),
            previous.isNotEmpty ? previous.first['created'] : nextOrder(),
          ],
        );
        if (draft != null) keepDraft(entity, draft);
        return id;
      });
  void attempted(String id) =>
      db.execute('UPDATE outbox SET attempted=1 WHERE id=?', [id]);
  void conflict(String id, String error) => db.execute(
    'UPDATE outbox SET state=\'conflict\', error=? WHERE id=?',
    [error, id],
  );
  void retry(String id) => db.execute(
    'UPDATE outbox SET state=\'queued\',error=NULL WHERE id=?',
    [id],
  );
  int nextOrder() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final previous = get('queueOrder') as int? ?? 0;
    final value = now > previous ? now : previous + 1;
    set('queueOrder', value);
    return value;
  }

  void resolve(String id, {Json? replacement}) => atomic(() {
    final item = queue.firstWhere((q) => q['id'] == id);
    final history = rows(get('conflictHistory'));
    history.add({
      ...item,
      'resolvedAt': DateTime.now().toUtc().toIso8601String(),
      'resolution': replacement == null ? 'kept_locally' : 'explicit_rebase',
    });
    set('conflictHistory', history);
    if (replacement != null) {
      db.execute(
        'UPDATE outbox SET id=?,body=?,state=\'queued\',error=NULL,attempted=0 WHERE id=?',
        [replacement['requestId'], jsonEncode(replacement), id],
      );
    } else {
      db.execute('DELETE FROM outbox WHERE id=?', [id]);
      db.execute('DELETE FROM drafts WHERE entity=?', [item['entity']]);
    }
  });
  void remapRef(String before, String after) {
    if (before == after) return;
    dynamic map(dynamic value) {
      if (value is List) return value.map(map).toList();
      if (value is Map) {
        return value.map(
          (k, v) => MapEntry(
            k,
            ['workRef', 'ownerRef'].contains(k) && v == before ? after : map(v),
          ),
        );
      }
      return value;
    }

    for (final item in queue.where((q) => q['attempted'] == 0)) {
      db.execute('UPDATE outbox SET body=? WHERE id=?', [
        jsonEncode(map(item['body'])),
        item['id'],
      ]);
    }
    final active = get('localActive');
    if (active is Map && active['workRef'] == before) {
      set('localActive', map(active));
    }
    final history = rows(get('localHistory'));
    if (history.any((s) => s['workRef'] == before)) {
      set('localHistory', map(history));
    }
  }

  void acknowledge(String id) => atomic(() {
    final r = db.select('SELECT entity FROM outbox WHERE id=?', [id]);
    db.execute('DELETE FROM outbox WHERE id=?', [id]);
    if (r.isNotEmpty &&
        db.select('SELECT id FROM outbox WHERE entity=?', [
          r.first['entity'],
        ]).isEmpty) {
      db.execute('DELETE FROM drafts WHERE entity=?', [r.first['entity']]);
    }
  });
  void finishLocal(Json finished, String? serverId) => atomic(() {
    final active = object(get('localActive'));
    if (active['id'] != finished['id']) {
      throw StateError('Активный сеанс изменился.');
    }
    set('localActive', null);
    final history = rows(get('localHistory'));
    history.add(finished);
    set('localHistory', history);
    if (finished['status'] == 'finished' &&
        finished['completedPomodoros'] == 1) {
      set('localPomodoroCount', (get('localPomodoroCount') as int? ?? 0) + 1);
    } else if (finished['status'] == 'finished' &&
        finished['phase'] == 'long_break') {
      set('localPomodoroCount', 0);
    }
    final id = uuid.v4();
    db.execute(
      'INSERT INTO outbox(id,entity,route,body,server_id,created) VALUES(?,?,?,?,?,?)',
      [
        id,
        'session:${finished['id']}',
        '/api/offline/import',
        jsonEncode({
          'serverId': serverId,
          'deviceId': get('deviceId'),
          'session': finished,
        }),
        serverId,
        nextOrder(),
      ],
    );
  });
  void exclude(String id) {
    final q = queue.firstWhere((q) => q['id'] == id);
    if (q['route'] != '/api/offline/import') {
      throw StateError('Можно исключить только сеанс.');
    }
    final body = {...object(q['body']), 'resolution': 'exclude'};
    db.execute(
      'UPDATE outbox SET body=?,state=\'queued\',error=NULL WHERE id=?',
      [jsonEncode(body), id],
    );
  }

  Json export() => {
    'version': 1,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'settings': db
        .select('SELECT * FROM kv')
        .map((r) => Map<String, dynamic>.from(r))
        .toList(),
    'snapshots': db
        .select('SELECT * FROM snapshots')
        .map((r) => Map<String, dynamic>.from(r))
        .toList(),
    'outbox': queue,
    'drafts': drafts,
  };
  void close() => db.close();
}
