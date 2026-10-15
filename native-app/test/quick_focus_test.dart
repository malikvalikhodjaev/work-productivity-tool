import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/repository.dart';

http.Client timerClient(Future<http.Response> Function(http.Request) handle) =>
    MockClient(
      (r) async => r.url.path == '/api/offline/connect'
          ? http.Response(jsonEncode({'serverId': 'owner-server'}), 200)
          : await handle(r),
    );

http.Response reply(LocalDatabase db, Json command) {
  final input = object(command['input']);
  final now = DateTime.now().millisecondsSinceEpoch;
  final active = command['action'] == 'resume'
      ? changeLocalSession(
          object(db.snapshot('timer')['active']),
          'resume',
          now,
        )
      : newLocalSession(
          title: input['title'],
          workRef: input['workRef'],
          metricId: input['metricId'],
          mode: input['mode'],
          settings: object(input['settings']),
          now: now,
        );
  return http.Response(
    jsonEncode({
      'revision': (db.snapshot('timer')['revision'] as int? ?? 0) + 1,
      'active': active,
      'sessions': [active],
      'settings': input['settings'] ?? timerDefaults,
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

LocalDatabase database() {
  final db = LocalDatabase(':memory:');
  db.set('serverId', 'owner-server');
  db.capture('timer', {
    'revision': 0,
    'settings': timerDefaults,
    'active': null,
  });
  return db;
}

void main() {
  test(
    'play starts selected work with saved duration and metadata in one command',
    () async {
      final db = database();
      db.capture('workspace', {
        'entities': [
          {
            'ref': 'work:one',
            'metricId': 'reading',
            'allocation': 'assigned',
            'workType': 'Применение · 应用',
          },
        ],
      });
      final commands = <Json>[];
      final repo = DashboardRepository(
        db,
        client: timerClient((r) async {
          final command = object(jsonDecode(r.body));
          commands.add(command);
          expect(db.get('pendingTimer'), command);
          return reply(db, command);
        }),
      )..online = true;
      addTearDown(repo.dispose);
      repo.setFocusPreferences({
        ...timerDefaults,
        'workMinutes': 50,
        'mode': 'pomodoro',
        'strategy': 'shared',
      });
      await repo.focusWork(ref: 'work:one', title: 'Мой выбранный фокус · 我的');
      expect(commands, hasLength(1));
      expect(commands.single['action'], 'start');
      final input = object(commands.single['input']);
      expect(input['workRef'], 'work:one');
      expect(input['metricId'], 'reading');
      expect(input['workType'], 'Применение · 应用');
      expect(repo.active?['plannedMs'], 50 * 60000);
      expect(repo.active?['title'], 'Мой выбранный фокус · 我的');
      expect(db.get('pendingTimer'), isNull);
    },
  );

  test(
    'play resumes same paused session and running play creates no duplicate',
    () async {
      final db = database();
      final now = DateTime.now().millisecondsSinceEpoch;
      final session = changeLocalSession(
        newLocalSession(title: 'Кейс', workRef: 'case:one', now: now - 60000),
        'pause',
        now - 30000,
      );
      db.capture('timer', {'revision': 4, 'active': session});
      final commands = <Json>[];
      final repo = DashboardRepository(
        db,
        client: timerClient((r) async {
          final command = object(jsonDecode(r.body));
          commands.add(command);
          return reply(db, command);
        }),
      )..online = true;
      addTearDown(repo.dispose);
      await repo.focusWork(ref: 'case:one', title: 'Кейс');
      await repo.focusWork(ref: 'case:one', title: 'Кейс');
      expect(commands.map((c) => c['action']), ['resume']);
      expect(repo.active?['id'], session['id']);
      expect(repo.active?['status'], 'running');
    },
  );

  test(
    'another active work is preserved without accounting or replacement',
    () async {
      final db = database();
      final session = newLocalSession(
        title: 'Первая',
        workRef: 'work:first',
        now: DateTime.now().millisecondsSinceEpoch,
      );
      db.capture('timer', {'revision': 1, 'active': session});
      var requests = 0;
      final repo = DashboardRepository(
        db,
        client: timerClient((_) async {
          requests++;
          return http.Response('{}', 500);
        }),
      )..online = true;
      addTearDown(repo.dispose);
      await expectLater(
        repo.focusWork(ref: 'case:second', title: 'Другая'),
        throwsStateError,
      );
      expect(repo.active, session);
      expect(requests, 0);
      expect(db.get('pendingTimer'), isNull);
    },
  );

  test('offline play needs explicitly selected device mode and remains recoverable', () async {
    final db = database();
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    await expectLater(
      repo.focusWork(ref: 'work:one', title: 'Без сети'),
      throwsStateError,
    );
    expect(repo.localActive, isNull);
    repo.setFocusPreferences({
      ...timerDefaults,
      'mode': 'pomodoro',
      'strategy': 'local',
    });
    await repo.focusWork(ref: 'work:one', title: 'Без сети');
    expect(repo.localActive?['workRef'], 'work:one');
    expect(db.get('localActive'), repo.localActive);
    expect(db.get('pendingTimer'), isNull);
  });

  test('two quick taps send one immutable start command', () async {
    final db = database();
    final gate = Completer<void>();
    var requests = 0;
    final repo = DashboardRepository(
      db,
      client: timerClient((r) async {
        requests++;
        await gate.future;
        return reply(db, object(jsonDecode(r.body)));
      }),
    )..online = true;
    addTearDown(repo.dispose);
    final first = repo.focusWork(ref: 'work:one', title: 'Фокус');
    final second = repo.focusWork(ref: 'work:one', title: 'Фокус');
    gate.complete();
    await Future.wait([first, second]);
    expect(requests, 1);
    expect(repo.focusStarting, false);
    expect(repo.active, isNotNull);
  });

  test('lost response retains request ID; another play cannot overwrite pending start', () async {
    final db = database();
    final commands = <String>[];
    var lost = true;
    final repo = DashboardRepository(
      db,
      client: timerClient((r) async {
        commands.add(r.body);
        if (lost) {
          lost = false;
          throw http.ClientException('Lost response');
        }
        return reply(db, object(jsonDecode(r.body)));
      }),
    )..online = true;
    addTearDown(repo.dispose);
    await expectLater(
      repo.focusWork(ref: 'work:one', title: 'Фокус'),
      throwsA(isA<http.ClientException>()),
    );
    final pending = jsonEncode(db.get('pendingTimer'));
    await expectLater(
      repo.focusWork(ref: 'work:two', title: 'Другой фокус'),
      throwsStateError,
    );
    expect(commands.last, pending);
    expect(db.get('pendingTimer'), isNull);
    await repo.checkPendingTimer();
    expect(commands, hasLength(2));
    expect(commands[0], commands[1]);
    expect(repo.active?['workRef'], 'work:one');
  });

  testWidgets('card play starts focus without a save or start form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = database();
    db.capture('workspace', {
      'cases': [
        {'id': 'one', 'title': 'Мой кейс', 'status': 'active'},
      ],
      'entities': [
        {'ref': 'case:one', 'title': 'Мой кейс'},
      ],
    });
    final repo = DashboardRepository(
      db,
      client: timerClient((r) async => reply(db, object(jsonDecode(r.body)))),
    )..online = true;
    await tester.pumpWidget(
      DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Работа').first);
    await tester.pump();
    final play = find.widgetWithText(TextButton, 'Фокус').first;
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Начать фокус'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.active?['workRef'], 'case:one');
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
  });
}
