import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/durable_timer.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/sync_panel.dart';

http.Response reply(Json value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json emptyTimer() => {
  'revision': 0,
  'settings': timerDefaults,
  'active': null,
  'sessions': [],
  'offlineCommands': true,
};
Json goal() => {
  'id': 'g',
  'title': 'Характеристика',
  'unit': 'ч',
  'direction': 'up',
  'status': 'active',
  'updatedAt': 'old',
};
void seed(LocalDatabase db) {
  db.set('serverId', 'owner');
  db.set('automaticSync', false);
  db.set('durableTimerEnabled', true);
  db.capture('timer', emptyTimer());
  db.capture('workspace', {
    'goals': [goal()],
    'goalGridVersion': 1,
    'goalFieldEditingVersion': 1,
    'goalTextLimits': {'unit': 200},
  });
}

Future<void> idle(DashboardRepository repo) async {
  for (
    var i = 0;
    i < 200 &&
        (repo.syncing || repo.pending.any((q) => q['state'] == 'queued'));
    i++
  ) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(repo.syncing, false);
}

void main() {
  for (final preexisting in [true, false]) {
    test(
      'a ${preexisting ? 'persisted' : 'new'} goal conflict does not hold independent timer actions',
      () async {
        final db = LocalDatabase(':memory:');
        seed(db);
        var timer = emptyTimer();
        final sent = <String>[], goalCommands = <Json>[];
        final repo = DashboardRepository(
          db,
          client: MockClient((r) async {
            if (r.url.path == '/api/offline/connect')
              return reply({'serverId': 'owner', 'offlineCommands': true});
            if (r.method == 'GET')
              return reply(r.url.path == '/api/timer' ? timer : {});
            final body = object(jsonDecode(r.body));
            if (r.url.path == '/api/native/command') {
              goalCommands.add(body);
              return reply({'error': 'Поле изменилось'}, 409);
            }
            sent.add(body['action'].toString());
            final input = object(body['input']);
            timer = projectTimer(
              timer,
              body['action'],
              input,
              input['occurredAt'],
            );
            return reply(timer);
          }),
        );
        addTearDown(repo.dispose);
        repo.editGoalField('g', 'title', 'Новое имя');
        final original = repo.pending.single;
        if (preexisting) {
          db.attempted(original['id'].toString());
          db.conflict(original['id'].toString(), 'Поле изменилось');
        }
        final raw = jsonEncode(original['body']);
        await repo.focusWork(ref: 'work:one', title: 'Работа');
        await repo.timerAction('pause');
        await repo.synchronize();
        expect(sent, ['start', 'pause']);
        expect(repo.pending, hasLength(1));
        expect(repo.pending.single['state'], 'conflict');
        expect(jsonEncode(repo.pending.single['body']), raw);
        expect(goalCommands, hasLength(preexisting ? 0 : 1));
        expect(repo.online, true);
        expect(db.get('lastSyncError'), isNull);
        expect(repo.active!['status'], 'paused');
        expect(repo.pomodoroFacts, isEmpty);
      },
    );
  }
  test('a conflicting timer still blocks the rest of its chain', () async {
    final db = LocalDatabase(':memory:');
    seed(db);
    final sent = <String>[];
    final repo = DashboardRepository(
      db,
      client: MockClient((r) async {
        if (r.url.path == '/api/offline/connect')
          return reply({'serverId': 'owner', 'offlineCommands': true});
        if (r.method == 'GET')
          return reply(r.url.path == '/api/timer' ? emptyTimer() : {});
        sent.add(object(jsonDecode(r.body))['action'].toString());
        return reply({'error': 'Другой сеанс'}, 409);
      }),
    );
    addTearDown(repo.dispose);
    await repo.focusWork(ref: 'work:one', title: 'Работа');
    await repo.timerAction('pause');
    await repo.synchronize();
    expect(sent, ['start']);
    expect(repo.pending, hasLength(2));
    expect(repo.pending.first['state'], 'conflict');
    expect(repo.pending.last['attempted'], 0);
    expect(repo.pomodoroFacts, isEmpty);
  });
  test('a new action queued during exchange drains automatically without another click or poll', () async {
    final db = LocalDatabase(':memory:');
    seed(db);
    db.set('automaticSync', true);
    var timer = emptyTimer();
    final started = Completer<void>(),
        hold = Completer<void>(),
        paused = Completer<void>();
    final sent = <String>[];
    final repo = DashboardRepository(
      db,
      client: MockClient((r) async {
        if (r.url.path == '/api/offline/connect')
          return reply({'serverId': 'owner', 'offlineCommands': true});
        if (r.method == 'GET')
          return reply(r.url.path == '/api/timer' ? timer : {});
        final body = object(jsonDecode(r.body)), input = object(body['input']);
        sent.add(body['action'].toString());
        timer = projectTimer(timer, body['action'], input, input['occurredAt']);
        if (body['action'] == 'start') {
          started.complete();
          await hold.future;
        }
        if (body['action'] == 'pause') paused.complete();
        return reply(timer);
      }),
    );
    addTearDown(repo.dispose);
    await repo.focusWork(ref: 'work:one', title: 'Работа');
    await started.future.timeout(const Duration(seconds: 5));
    await repo.timerAction('pause');
    expect(repo.pending, hasLength(2));
    hold.complete();
    await paused.future.timeout(const Duration(seconds: 5));
    await idle(repo);
    expect(repo.pending, isEmpty);
    expect(sent, ['start', 'pause']);
    expect(repo.active!['status'], 'paused');
  });
  test('upgrade reopens the same database and repeats the legacy rejection without rewriting its command', () async {
    final dir = Directory.systemTemp.createTempSync('iw-upgrade-');
    addTearDown(() {
      expect(
        dir.absolute.path.startsWith(
          '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
        ),
        true,
      );
      dir.deleteSync(recursive: true);
    });
    final file = '${dir.path}/device.sqlite';
    var db = LocalDatabase(file);
    seed(db);
    final rejected = {
      'requestId': uuid.v4(),
      'serverId': 'owner',
      'deviceId': db.get('deviceId'),
      'module': 'workspace',
      'action': 'saveGoal',
      'expectedUpdatedAt': 'old',
      'input': {...goal(), 'unit': 'суммарное количество часов в неделю'},
    };
    final id = db.enqueue(
      'goal:g',
      '/api/native/command',
      rejected,
      draft: object(rejected['input']),
    );
    db.attempted(id);
    db.conflict(id, 'Единица: не больше 30 символов.');
    db.set('goalInline:owner:g:unit', {
      'text': '  Незавершённый текст  ',
      'base': goal(),
    });
    var repo = DashboardRepository(db);
    await repo.focusWork(ref: 'work:one', title: 'Работа');
    await repo.timerAction('pause');
    final device = repo.deviceId,
        original = repo.pending.map((q) => jsonEncode(q['body'])).toList();
    repo.dispose();
    db = LocalDatabase(file);
    var timer = emptyTimer(),
        workspace = <String, dynamic>{
          'goals': [goal()],
          'goalTextLimits': {'unit': 200},
          'goalGridVersion': 1,
          'goalFieldEditingVersion': 1,
        };
    final received = <String>[];
    repo = DashboardRepository(
      db,
      client: MockClient((r) async {
        if (r.url.path == '/api/offline/connect')
          return reply({'serverId': 'owner', 'offlineCommands': true});
        if (r.method == 'GET')
          return reply(
            r.url.path == '/api/timer'
                ? timer
                : r.url.path == '/api/workspace'
                ? workspace
                : {},
          );
        received.add(jsonEncode(object(jsonDecode(r.body))));
        final body = object(jsonDecode(r.body)), input = object(body['input']);
        if (r.url.path == '/api/native/command') {
          workspace = {
            ...workspace,
            'goals': [
              {...input, 'updatedAt': 'accepted'},
            ],
          };
          return reply({'workspace': workspace});
        }
        timer = projectTimer(timer, body['action'], input, input['occurredAt']);
        return reply(timer);
      }),
    );
    addTearDown(repo.dispose);
    await repo.synchronize();
    expect(received, original);
    expect(repo.pending, isEmpty);
    expect(repo.deviceId, device);
    expect(repo.serverId, 'owner');
    expect(
      object(db.get('goalInline:owner:g:unit'))['text'],
      '  Незавершённый текст  ',
    );
    expect(
      object(rows(db.get('goalValidationReplayHistory')).single['body']),
      rejected,
    );
    expect(repo.active!['status'], 'paused');
    expect(repo.pomodoroFacts, isEmpty);
  });
  testWidgets(
    'working timer has no sync controls or pending captions; service panel retains them',
    (tester) async {
      final db = LocalDatabase(':memory:');
      seed(db);
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      await repo.focusWork(ref: 'work:one', title: 'Работа');
      db.set('focusMode', true);
      await tester.pumpWidget(
        DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
      );
      await tester.pump();
      expect(find.text('Синхронизировать'), findsNothing);
      expect(find.textContaining('действий ждут синхронизации'), findsNothing);
      expect(find.textContaining('сохранение на устройстве'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SyncPanel(repo: repo)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Синхронизировать'), findsOneWidget);
      expect(find.textContaining('Ожидает отправки: 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
