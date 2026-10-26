import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/pomodoro_widgets.dart';
import 'package:indicators_work/timer_command_notice.dart';
import 'package:indicators_work/time_type_picker.dart';

LocalDatabase fixture() {
  final db = LocalDatabase(':memory:')
    ..set('serverId', 'demo')
    ..set('automaticSync', false)
    ..set('timerStrategy', 'local');
  db.capture('workspace', {
    'entities': [
      {'ref': 'work:invest', 'title': 'Учёба', 'workType': 'investment'},
      {'ref': 'work:football', 'title': 'Футбол', 'workType': 'productive'},
      {'ref': 'work:unknown', 'title': 'Разобрать'},
    ],
  });
  db.capture('dailyNorms', {
    'pomodoroTargets': [
      {
        'date': today(),
        'repeat': 'daily',
        'workRef': 'work:invest',
        'title': 'Учёба',
        'target': 3,
      },
      {
        'date': today(),
        'repeat': 'daily',
        'workRef': 'work:football',
        'title': 'Футбол',
        'target': 1,
        'workType': 'leisure',
      },
      {
        'date': today(),
        'repeat': 'daily',
        'workRef': 'work:unknown',
        'title': 'Разобрать',
        'target': 1,
      },
    ],
    'pomodoroCapacities': [
      {'date': today(), 'limit': 8},
    ],
  });
  return db;
}

Widget screen(DashboardRepository repo) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: PomodoroChecklist(repo: repo, compact: true, rowsFirst: true),
    ),
  ),
);
void main() {
  test('norm category uses explicit override, inherited work type and unknown without rewriting input', () {
    final db = fixture();
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    final norms = repo.pomodoroTargetsForDate();
    expect(norms.map((n) => normTimeCategory(repo, n)), [
      'investment',
      'leisure',
      'unclassified',
    ]);
    expect(norms.first.containsKey('workType'), false);
    expect(db.drafts, isEmpty);
    expect(repo.pending, isEmpty);
  });
  testWidgets(
    'category filters persist, active norm stays highlighted, total cap and session remain unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = fixture();
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      await repo.focusWork(ref: 'work:invest', title: 'Учёба');
      final id = repo.active!['id'];
      final cap = repo.pomodoroCapacityForDate();
      await tester.pumpWidget(screen(repo));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('norm-filters-bottom'))).dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.byKey(const ValueKey('pomodoro-row:work:unknown')),
              )
              .dy,
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('norm-filter:leisure')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('norm-filter:leisure')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('pomodoro-title:work:football')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pomodoro-title:work:invest')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('pomodoro-title:work:unknown')),
        findsNothing,
      );
      expect(repo.active!['id'], id);
      expect(repo.pomodoroCapacityForDate(), cap);
      expect(repo.pending, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen(repo));
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('norm-filter:leisure')),
            )
            .selected,
        true,
      );
      await tester.tap(find.text('Показать активный норматив'));
      await tester.pump();
      final row = find.byKey(const ValueKey('pomodoro-row:work:invest'));
      expect(row, findsOneWidget);
      final decoration =
          tester.widget<Container>(row).decoration! as BoxDecoration;
      expect(decoration.color!.a, greaterThan(0));
      expect((decoration.border! as Border).top.width, 2);
      await repo.timerAction('pause');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('pomodoro-row:work:invest')),
        findsOneWidget,
      );
      expect(repo.active!['status'], 'paused');
      await tester.ensureVisible(
        find.byKey(const ValueKey('norm-filter:unclassified')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('norm-filter:unclassified')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('pomodoro-title:work:unknown')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'plus in Leisure preselects Leisure without creating a norm or changing active timer',
    (tester) async {
      final db = fixture()..set('normTimeFilter', 'leisure');
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      await tester.pumpWidget(screen(repo));
      await tester.tap(find.byTooltip('Норматив на день'));
      await tester.pumpAndSettle();
      final picker = tester.widget<TimeTypePicker>(find.byType(TimeTypePicker));
      expect(picker.value, 'leisure');
      expect(repo.pending, isEmpty);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(repo.pomodoroTargetsForDate().length, 3);
    },
  );
  testWidgets(
    'running timer adds no duplicate status but pending commands keep recovery notice',
    (tester) async {
      final db = fixture();
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      await repo.focusWork(ref: 'work:invest', title: 'Учёба');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimerCommandNotice(repo: repo, retry: () {}),
          ),
        ),
      );
      expect(find.textContaining('Таймер запущен'), findsNothing);
      expect(find.text('Учёба'), findsNothing);
      await repo.timerAction('cancel');
      db.set('durableTimerEnabled', true);
      db.set('timerStrategy', 'shared');
      await repo.focusWork(ref: 'work:invest', title: 'Учёба');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimerCommandNotice(repo: repo, retry: () {}),
          ),
        ),
      );
      expect(find.textContaining('Сохранено на устройстве'), findsOneWidget);
    },
  );
}
