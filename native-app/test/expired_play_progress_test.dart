import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/active_timer_conflict.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/pomodoro_widgets.dart';
import 'package:indicators_work/repository.dart';

void main() {
  test(
    'expired Play preserves the session and cannot silently succeed',
    () async {
      final db = LocalDatabase(':memory:');
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      final session = newLocalSession(
        title: 'Моя работа',
        workRef: 'case:one',
        now: repo.now - 30 * 60000,
      );
      db.capture('timer', {'revision': 1, 'active': session});
      final before = jsonEncode(db.snapshot('timer'));
      for (final ref in ['case:one', 'case:other']) {
        await expectLater(
          repo.focusWork(ref: ref, title: 'Моя работа'),
          throwsA(isA<ExpiredTimerConflict>()),
        );
      }
      expect(jsonEncode(db.snapshot('timer')), before);
      expect(db.queue, isEmpty);
    },
  );

  testWidgets(
    'wide desktop Play opens expired review with explicit next start',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = LocalDatabase(':memory:');
      db.set('durableTimerEnabled', true);
      db.set('serverId', 'owner-server');
      final repo = DashboardRepository(
        db,
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      final session = newLocalSession(
        title: 'Моя работа',
        workRef: 'case:one',
        now: repo.now - 30 * 60000,
      );
      db.capture('timer', {'revision': 1, 'active': session});
      db.capture('workspace', {
        'cases': [
          {'id': 'one', 'title': 'Моя работа', 'status': 'active'},
        ],
        'entities': [
          {'ref': 'case:one', 'title': 'Моя работа'},
        ],
      });
      await tester.pumpWidget(
        DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
      );
      await tester.tap(find.text('Работа').last);
      await tester.pump();
      await tester.ensureVisible(find.text('Фокус').first);
      await tester.tap(find.text('Фокус').first);
      await tester.pumpAndSettle();
      expect(find.text('Как прошла помидорка?'), findsOneWidget);
      expect(find.text('Учесть и запустить'), findsOneWidget);
      expect(find.byTooltip('Все разделы'), findsOneWidget);
      expect(repo.active?['id'], session['id']);
      expect(db.queue, isEmpty);
      await tester.tap(find.text('Учесть и запустить'));
      await tester.pumpAndSettle();
      expect(repo.active?['id'], isNot(session['id']));
      expect(repo.active?['workRef'], 'case:one');
      expect(repo.active?['plannedMs'], 25 * 60000);
      expect(elapsedMs(repo.active!, repo.now), lessThan(5000));
      expect(clockOf(repo.active!, repo.now), isNot('00:00'));
      expect(
        repo.pomodoroFacts.where((f) => f['sessionId'] == session['id']),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  testWidgets('progress shows zero, limit and overflow on compact widths', (
    tester,
  ) async {
    for (final actual in [0, 15, 18]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              child: PomodoroCapacityProgress(actual: actual, limit: 15),
            ),
          ),
        ),
      );
      expect(
        find.text('Сделано $actual / 15 · ${(actual * 100 / 15).round()}%'),
        findsOneWidget,
      );
      expect(
        find.text(
          actual == 0
              ? 'До лимита: 15 (6,25 ч)'
              : actual == 15
              ? 'Дневной лимит достигнут'
              : '+3 сверх лимита (1,25 ч)',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  test('daily limit includes work without a norm and deduplicates facts', () {
    final db = LocalDatabase(':memory:');
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    db.capture('dailyNorms', {
      'pomodoroCapacities': [
        {'date': today(), 'limit': 1},
      ],
      'pomodoroFacts': [
        {'sessionId': 'a', 'workRef': 'work:unplanned', 'date': today()},
        {'sessionId': 'a', 'workRef': 'work:unplanned', 'date': today()},
        {'sessionId': 'b', 'workRef': 'work:unplanned', 'date': today()},
        {'sessionId': 'old', 'workRef': 'work:unplanned', 'date': '2000-01-01'},
      ],
    });
    expect(repo.pomodoroCapacityForDate()['actualPomodoros'], 2);
  });
}
