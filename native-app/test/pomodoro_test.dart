import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/pomodoro_plan.dart';
import 'package:indicators_work/repository.dart';

void main() {
  DashboardRepository repository(LocalDatabase db) => DashboardRepository(
    db,
    client: MockClient(
      (_) async => http.Response(jsonEncode({'error': 'Offline'}), 503),
    ),
  );

  test('full sessions count once across cached and offline copies, midnight uses UTC+5', () {
    final db = LocalDatabase(':memory:');
    db.set('serverId', 'owner');
    final repo = repository(db);
    final start = DateTime.parse('2026-10-15T18:50:00Z').millisecondsSinceEpoch;
    final finished = changeLocalSession(
      newLocalSession(title: 'Модель', workRef: 'case:a', now: start),
      'finish',
      start + 25 * 60000,
      observation: 'Готово',
    );
    final fact = pomodoroFact(finished)!;
    expect(fact['date'], '2026-10-16');
    db.capture('dailyNorms', {
      'pomodoroTargets': [
        {
          'date': '2026-10-16',
          'workRef': 'case:a',
          'title': '  Мой норматив  ',
          'target': 1,
        },
      ],
      'pomodoroFacts': [fact],
    });
    db.enqueue('session:${finished['id']}', '/api/offline/import', {
      'session': finished,
    }, draft: finished);
    expect(
      repo.pomodoroTargetsForDate('2026-10-16').single['actualPomodoros'],
      1,
    );
    expect(repo.hasPomodoroPlan, false);
    expect(pomodoroFact({...finished, 'completedPomodoros': 0}), isNull);
    expect(pomodoroFact({...finished, 'syncResolution': 'excluded'}), isNull);
    final week = pomodoroWeekRows(repo.pomodoroRows, [
      fact,
      fact,
    ], '2026-10-16');
    expect(week.single['actualPomodoros'], 1);
    expect(week.single['target'], 1);
    expect(week.single['title'], '  Мой норматив  ');
    repo.dispose();
  });

  testWidgets(
    '0/1 and 0/10 are visible in the overlay and settings; snooze suppresses hourly reopening',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = LocalDatabase(':memory:');
      db.set('serverId', 'owner');
      db.capture('dailyNorms', {
        'pomodoroTargets': [
          {
            'date': today(),
            'workRef': 'case:a',
            'title': 'Читать руководства',
            'target': 1,
          },
          {
            'date': today(),
            'workRef': 'case:b',
            'title': 'Работа над системой',
            'target': 10,
          },
        ],
      });
      final repo = repository(db);
      await tester.pumpWidget(
        DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Сделал это?'), findsOneWidget);
      expect(find.text('0/1'), findsWidgets);
      expect(find.text('0/10'), findsWidgets);
      await tester.tap(find.text('Скрыть · до следующего часа'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Сделал это?'), findsNothing);
      await tester.tap(find.byTooltip('Настройки и нормативы'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Настройки · нормативы на день'), findsOneWidget);
      expect(find.text('Читать руководства'), findsWidgets);
      expect(find.text('0/10'), findsWidgets);
      expect(find.text('Помидорки за неделю'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  testWidgets(
    'missing plan asks on entry and stops after one positive local target',
    (tester) async {
      final db = LocalDatabase(':memory:');
      db.set('serverId', 'owner');
      db.capture('dailyNorms', {'pomodoroTargets': []});
      final repo = repository(db);
      await tester.pumpWidget(
        DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Вы поставили нормативы на день?'), findsOneWidget);
      await tester.tap(find.text('Позже · через час'));
      await tester.pump(const Duration(milliseconds: 350));
      db.keepDraft('pomodoro:${today()}:case:a', {
        'date': today(),
        'workRef': 'case:a',
        'title': 'Моя норма',
        'target': 1,
      });
      expect(repo.hasPomodoroPlan, true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Вы поставили нормативы на день?'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
}
