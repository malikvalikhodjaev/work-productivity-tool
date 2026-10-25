import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/dashboard_timer_bar.dart';
import 'package:indicators_work/adaptive_focus_player.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/pomodoro_widgets.dart';

LocalDatabase fixture() {
  final db = LocalDatabase(':memory:')
    ..set('serverId', 'demo')
    ..set('automaticSync', false)
    ..set('timerStrategy', 'local');
  db.capture('workspace', {
    'entities': [
      {'ref': 'work:one', 'title': 'Проект', 'workType': 'productive'},
    ],
  });
  db.capture('dailyNorms', {
    'pomodoroTargets': [
      {
        'date': today(),
        'repeat': 'daily',
        'workRef': 'work:one',
        'title': 'Проект',
        'target': 10,
        'workType': 'investment',
      },
    ],
  });
  return db;
}

void main() {
  test('new sessions use norm type, active session is unchanged and blank inherits work', () async {
    final db = fixture();
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    await repo.focusWork(ref: 'work:one', title: 'Проект');
    expect(repo.active!['workType'], 'investment');
    db.capture('dailyNorms', {
      'pomodoroTargets': [
        {
          'date': today(),
          'repeat': 'daily',
          'workRef': 'work:one',
          'title': 'Проект',
          'target': 10,
          'workType': '',
        },
      ],
    });
    expect(repo.active!['workType'], 'investment');
    await repo.timerAction('cancel');
    await repo.focusWork(ref: 'work:one', title: 'Проект');
    expect(repo.active!['workType'], 'productive');
  });
  testWidgets(
    'norm editor keeps selected type in local command and visible checklist',
    (tester) async {
      final db = fixture();
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => editPomodoroTarget(
                  context,
                  repo,
                  previous: repo.pomodoroTargetsForDate().first,
                ),
                child: const Text('Править'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Править'));
      await tester.pumpAndSettle();
      final type = find.byKey(const ValueKey('time-type:investment'));
      await tester.ensureVisible(type);
      await tester.tap(type);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('time-type:leisure')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.pomodoroTargetsForDate().first['workType'], 'leisure');
      expect(
        object(repo.pending.single['body'])['input']['workType'],
        'leisure',
      );
    },
  );
  testWidgets(
    'timer remains live while dashboard tab content changes and pause is explicit',
    (tester) async {
      final db = fixture();
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      await repo.focusWork(ref: 'work:one', title: 'Проект');
      final id = repo.active!['id'];
      final pulse = ChangeNotifier();
      addTearDown(pulse.dispose);
      var tab = 0;
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              change = set;
              return Scaffold(
                body: Column(
                  children: [
                    Expanded(child: Text('Раздел $tab')),
                    DashboardTimerBar(
                      repo: repo,
                      pulse: pulse,
                      open: () {},
                      pause: () => repo.timerAction('pause'),
                      finish: () {},
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('dashboard-timer-clock')),
        findsOneWidget,
      );
      change(() => tab = 3);
      await tester.pump();
      expect(find.text('Раздел 3'), findsOneWidget);
      expect(repo.active!['id'], id);
      await tester.tap(find.text('Пауза'));
      pulse.notifyListeners();
      await tester.pump();
      expect(find.text('Продолжить'), findsOneWidget);
      expect(find.textContaining('На паузе'), findsOneWidget);
    },
  );
  testWidgets(
    'full window keeps three norms fully visible and large clock centered',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = fixture();
      db.capture('dailyNorms', {
        'pomodoroTargets': [
          for (var i = 0; i < 3; i++)
            {
              'date': today(),
              'repeat': 'daily',
              'workRef': 'work:$i',
              'title': 'Норматив $i',
              'target': 10,
            },
        ],
        'pomodoroCapacities': [
          {'date': today(), 'limit': 8},
        ],
      });
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveFocusPlayer(
              changes: repo,
              clock: '24:17',
              mode: '',
              weeklyProblem: 'Продвинуть проект',
              dailyProblem: 'Проверить изменение',
              contextPanel: const Text('Контекст'),
              description: const SizedBox.shrink(),
              actions: Wrap(
                spacing: 10,
                children: [
                  FilledButton(onPressed: () {}, child: const Text('Пауза')),
                  FilledButton(onPressed: () {}, child: const Text('Учесть')),
                ],
              ),
              norms: PomodoroChecklist(
                repo: repo,
                compact: true,
                rowsFirst: true,
              ),
              settings: const Text('Настройки'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Норматив 2').hitTestable(), findsOneWidget);
      expect(find.text('Настройки таймера').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('focus-checklist-scroll')),
        findsNothing,
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('focus-clock'))).dx,
        closeTo(750, 1),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('focus-clock'))).height,
        greaterThan(100),
      );
    },
  );
}
