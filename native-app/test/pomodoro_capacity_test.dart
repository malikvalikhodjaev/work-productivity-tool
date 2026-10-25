import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/focus_repository.dart';
import 'package:indicators_work/pomodoro_plan.dart';
import 'package:indicators_work/pomodoro_widgets.dart';

void main() {
  testWidgets('norm editor previews total without counting edited work twice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = LocalDatabase(':memory:');
    final repo = FocusRepository(db);
    final day = today();
    db.capture('workspace', {
      'entities': [
        {'ref': 'work:a', 'title': 'A'},
        {'ref': 'work:b', 'title': 'B'},
      ],
    });
    db.capture('dailyNorms', {
      'pomodoroTargets': [
        {
          'date': day,
          'repeat': 'daily',
          'workRef': 'work:a',
          'title': 'A',
          'target': 10,
        },
        {
          'date': day,
          'repeat': 'daily',
          'workRef': 'work:b',
          'title': 'B',
          'target': 8,
        },
      ],
      'pomodoroCapacities': [
        {'date': day, 'limit': 15},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => editPomodoroTarget(
                context,
                repo,
                previous: repo.pomodoroTargetsForDate().last,
              ),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('В плане сейчас 18 помидорок'), findsOneWidget);
    final target = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == 'Помидорок за день · пусто для снятия',
    );
    await tester.enterText(target, '5');
    await tester.pump();
    expect(
      find.textContaining('План: 15 помидорок · твой лимит: 15 в день.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(repo.pomodoroCapacityForDate()['planned'], 15);
    expect(repo.pomodoroTargetsForDate().first['target'], 10);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
  });
  const day = '2026-10-21';
  final targets = <Json>[
    {'workRef': 'task:a', 'target': 10},
    {'workRef': 'task:b', 'target': 8},
  ];
  final rules = <Json>[
    {'date': day, 'limit': 15},
    {'date': '2026-10-23', 'limit': 30},
    {'date': '2026-10-24', 'limit': null},
  ];
  test('daily total, replacement preview and historical capacity', () {
    expect(pomodoroCapacitySummary(targets, rules, day)['over'], true);
    expect(
      pomodoroCapacitySummary(
        targets,
        rules,
        day,
        candidate: {'workRef': 'task:b', 'target': 5},
      )['planned'],
      15,
    );
    expect(
      pomodoroCapacitySummary(
        targets,
        rules,
        day,
        candidate: {'workRef': 'task:b', 'target': 5},
      )['over'],
      false,
    );
    expect(pomodoroCapacityOn(rules, '2026-10-20'), null);
    expect(pomodoroCapacityOn(rules, '2026-10-23'), 30);
    expect(pomodoroCapacityOn(rules, '2036-01-01'), null);
  });
  test('offline capacity is durable draft and never overwritten by a stale snapshot', () async {
    final db = LocalDatabase(':memory:')..set('serverId', 'owner');
    final repo = DashboardRepository(
      db,
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    repo.nativeSave('pomodoroCapacity', 'save', {
      'date': day,
      'limit': 15,
    }, 'capacity:$day');
    db.capture('dailyNorms', {'pomodoroCapacities': <Json>[]});
    expect(repo.pomodoroCapacityForDate(day)['limit'], 15);
    expect(object(repo.pending.single['body'])['module'], 'pomodoroCapacity');
    expect(repo.pending.single['server_id'], 'owner');
    expect(
      () => repo.nativeSave('pomodoroCapacity', 'save', {
        'date': day,
        'limit': 0,
      }, 'capacity:$day'),
      throwsArgumentError,
    );
    await Future<void>.delayed(Duration.zero);
    repo.dispose();
  });
  test('standalone edition persists capacity locally with no outbox', () {
    final db = LocalDatabase(':memory:');
    final repo = FocusRepository(db);
    repo.nativeSave('pomodoroCapacity', 'save', {
      'date': day,
      'limit': 15,
    }, 'capacity:$day');
    expect(repo.pomodoroCapacityForDate(day)['limit'], 15);
    expect(db.queue, isEmpty);
    final saved = rows(repo.cache('dailyNorms')['pomodoroCapacities']).single;
    expect(
      () => repo.nativeSave('pomodoroCapacity', 'save', {
        'date': day,
        'limit': 30,
      }, 'capacity:$day'),
      throwsStateError,
    );
    repo.nativeSave(
      'pomodoroCapacity',
      'save',
      {'date': day, 'limit': 30},
      'capacity:$day',
      expectedUpdatedAt: saved['updatedAt'],
    );
    expect(repo.pomodoroCapacityForDate(day)['limit'], 30);
    repo.dispose();
  });
}
