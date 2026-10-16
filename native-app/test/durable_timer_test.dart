import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/durable_timer.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';

http.Response response(Json body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void seed(LocalDatabase db) {
  db.set('serverId', 'owner');
  db.set('automaticSync', false);
  db.set('durableTimerEnabled', true);
  db.capture('timer', {
    'revision': 0,
    'settings': timerDefaults,
    'active': null,
    'sessions': [],
  });
}

void main() {
  test('offline start, pause, resume and finish survive restart; lost reply keeps immutable commands', () async {
    final directory = Directory.systemTemp.createTempSync('iw-durable-timer-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = '${directory.path}/device.sqlite';
    var db = LocalDatabase(file);
    seed(db);
    var calls = 0;
    var repo = DashboardRepository(
      db,
      client: MockClient((_) async {
        calls++;
        return response({}, 503);
      }),
    );
    db.set('serverOffset', -120000);
    await repo.focusWork(ref: 'work:real', title: 'Работа без связи');
    final id = repo.active!['id'];
    db.set('serverOffset', -90000);
    await repo.timerAction('pause');
    expect(repo.active!['status'], 'paused');
    db.set('serverOffset', -60000);
    await repo.timerAction('resume');
    db.set('serverOffset', 0);
    await repo.timerAction('finish', observation: '  Всё сохранилось · 思考  ');
    expect(repo.active, isNull);
    expect(repo.pending.length, 4);
    expect(calls, 0);
    final original = repo.pending.map((p) => jsonEncode(p['body'])).toList();
    expect(
      rows(repo.cache('timer')['sessions']).single['observation'],
      '  Всё сохранилось · 思考  ',
    );
    expect(
      elapsedMs(rows(repo.cache('timer')['sessions']).single, repo.now),
      closeTo(90000, 1000),
    );
    repo.dispose();

    db = LocalDatabase(file);
    var state = <String, dynamic>{
      'revision': 0,
      'settings': timerDefaults,
      'active': null,
      'sessions': [],
    };
    final receipts = <String>{};
    final received = <String>[];
    var lose = true;
    repo = DashboardRepository(
      db,
      client: MockClient((r) async {
        if (r.url.path == '/api/offline/connect') {
          return response({'serverId': 'owner', 'offlineCommands': true});
        }
        if (r.method == 'GET') {
          return response(r.url.path == '/api/timer' ? state : {});
        }
        final command = object(jsonDecode(r.body)),
            input = object(command['input']);
        received.add(r.body);
        if (receipts.add(input['requestId'].toString())) {
          expect(input['expectedRevision'], state['revision']);
          state = projectTimer(
            state,
            command['action'],
            input,
            input['occurredAt'],
          );
        }
        if (lose) {
          lose = false;
          throw http.ClientException('Reply lost after commit');
        }
        return response(state);
      }),
    );
    expect(repo.active, isNull);
    expect(repo.pending.map((p) => jsonEncode(p['body'])).toList(), original);
    await repo.synchronize();
    expect(repo.pending.length, 4);
    expect(repo.pending.first['attempted'], 1);
    await repo.synchronize();
    expect(repo.pending, isEmpty);
    expect(received[0], received[1]);
    expect(receipts.length, 4);
    expect(rows(repo.cache('timer')['sessions']).single['id'], id);
    expect(
      rows(repo.cache('timer')['sessions']).single['observation'],
      '  Всё сохранилось · 思考  ',
    );
    expect(db.get('optimisticTimer'), isNull);
    expect(
      rows(db.get('sharedLocalHistory')).single['observation'],
      '  Всё сохранилось · 思考  ',
    );
    expect(object(db.get('timerCommandReceipts')).length, 4);
    repo.dispose();
  });

  test(
    'network wait never blocks the next pause, resume or local completion',
    () async {
      final db = LocalDatabase(':memory:');
      seed(db);
      db.set('automaticSync', true);
      final waiting = Completer<http.Response>();
      final repo = DashboardRepository(
        db,
        client: MockClient((_) => waiting.future),
      );
      await repo
          .focusWork(ref: 'work:one', title: 'Фокус')
          .timeout(const Duration(seconds: 1));
      await repo.timerAction('pause').timeout(const Duration(seconds: 1));
      await repo.timerAction('resume').timeout(const Duration(seconds: 1));
      await repo
          .timerAction('finish', observation: 'Сохранил локально')
          .timeout(const Duration(seconds: 1));
      expect(repo.active, isNull);
      expect(repo.timerBusy, false);
      expect(repo.pending.length, 4);
      waiting.complete(response({}, 503));
      while (repo.syncing) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(repo.pending.length, 4);
      expect(repo.status, contains('сохранены на устройстве'));
      repo.dispose();
    },
  );

  test('version conflict retains local completed pomodoro but does not count it as confirmed', () async {
    final db = LocalDatabase(':memory:');
    seed(db);
    db.capture('dailyNorms', {
      'pomodoroTargets': [
        {'date': today(), 'workRef': 'work:one', 'target': 1, 'title': 'Норма'},
      ],
    });
    final repo = DashboardRepository(
      db,
      client: MockClient((r) async {
        if (r.url.path == '/api/offline/connect') {
          return response({'serverId': 'owner', 'offlineCommands': true});
        }
        if (r.method == 'POST') {
          return response({'error': 'Другая версия'}, 409);
        }
        return response(
          r.url.path == '/api/daily-norms' ? db.snapshot('dailyNorms') : {},
        );
      }),
    );
    db.set('serverOffset', -1600000);
    await repo.focusWork(ref: 'work:one', title: 'Норма');
    db.set('serverOffset', 0);
    await repo.timerAction('finish', observation: 'Локальный результат');
    expect(repo.pomodoroTargetsForDate().single['pendingPomodoros'], 1);
    await repo.synchronize();
    expect(repo.pending.first['state'], 'conflict');
    expect(repo.pomodoroTargetsForDate().single['actualPomodoros'], 0);
    expect(
      rows(repo.cache('timer')['sessions']).single['observation'],
      'Локальный результат',
    );
    // A rejected predecessor blocks the entire dependent chain from confirmation.
    expect(repo.local.get('optimisticTimer'), isNotNull);
    repo.dispose();
  });

  test('another server receives no saved command and cannot replace the local timer', () async {
    final db = LocalDatabase(':memory:');
    seed(db);
    var writes = 0;
    final repo = DashboardRepository(
      db,
      client: MockClient((r) async {
        if (r.url.path == '/api/offline/connect') {
          return response({'serverId': 'other', 'offlineCommands': true});
        }
        writes++;
        return response({});
      }),
    );
    await repo.focusWork(ref: 'work:one', title: 'Моя работа');
    final id = repo.active!['id'];
    await repo.synchronize();
    expect(writes, 0);
    expect(repo.active!['id'], id);
    expect(repo.pending.length, 1);
    repo.dispose();
  });
}
