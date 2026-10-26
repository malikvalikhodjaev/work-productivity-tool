import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/app_appearance.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/goal_progress.dart';
import 'package:indicators_work/goal_table.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/section_navigation.dart';

class MeasurementClock extends DashboardRepository {
  int clock;
  MeasurementClock(super.local, this.clock);
  @override
  int get now => clock;
}

void main() {
  test(
    'current value creates immutable dated history across local midnight',
    () {
      final db = LocalDatabase(':memory:')
        ..set('automaticSync', false)
        ..set('serverId', 'owner');
      final repo = MeasurementClock(
        db,
        DateTime.utc(2026, 10, 26, 18, 59).millisecondsSinceEpoch,
      );
      addTearDown(repo.dispose);
      final goal = <String, dynamic>{
        'id': 'g',
        'unit': 'клиентов',
        'target': 30,
        'direction': 'up',
      };
      db.capture('workspace', {
        'goals': [goal],
        'measurements': [],
      });
      final snapshot = jsonEncode(db.snapshot('workspace'));
      repo.recordGoalMeasurement(goal, 10, evidence: '  исходный\n текст  ');
      final first = jsonEncode(repo.pending.single['body']);
      repo.clock = DateTime.utc(2026, 10, 26, 19, 1).millisecondsSinceEpoch;
      repo.recordGoalMeasurement(goal, 20);
      expect(repo.pending, hasLength(2));
      expect(jsonEncode(repo.pending.first['body']), first);
      final bodies = repo.pending
          .map((q) => object(object(q['body'])['input']))
          .toList();
      expect(bodies.map((b) => b['date']), ['2026-10-26', '2026-10-27']);
      expect(bodies.first['evidence'], '  исходный\n текст  ');
      expect(jsonEncode(db.snapshot('workspace')), snapshot);
      final projected = projectedGoals(repo).single;
      expect(projected['current'], 20);
      expect(projected['baseline'], isNull);
      expect(projected['comparisonBaseline'], 10);
      expect(projected['delta'], 10);
      expect(projected['changePercent'], 100);
      expect(projected['percent'], 50);
    },
  );

  test(
    'stored baseline survives; zero, decreasing and overshoot stay meaningful',
    () {
      final goal = evaluateGoal(
        {'baseline': 20, 'target': 10, 'direction': 'down'},
        [
          {'value': 5},
          {'value': 18},
        ],
      );
      expect(goal['comparisonBaseline'], 20);
      expect(goal['delta'], -15);
      expect(goal['percent'], 150);
      expect(goal['changePercent'], -75);
      expect(
        evaluateGoal(
          {'target': 10},
          [
            {'value': 5},
            {'value': 0},
          ],
        )['changePercent'],
        isNull,
      );
    },
  );

  for (final size in [const Size(360, 780), const Size(320, 780)]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('navigation stays single-line at $size and text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = 0;
        const labels = ['Показатели', 'Проекты', 'Работа', 'Письмо', 'Данные'];
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                bottomNavigationBar: SectionNavigation(
                  labels: labels,
                  icons: const [
                    Icons.insights,
                    Icons.account_tree,
                    Icons.work,
                    Icons.edit,
                    Icons.table_chart,
                  ],
                  selected: selected,
                  select: (i) => selected = i,
                ),
              ),
            ),
          ),
        );
        for (final label in labels) {
          final text = tester.widget<Text>(find.text(label));
          expect(text.maxLines, 1);
          expect(text.softWrap, false);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
        }
        await tester.ensureVisible(find.byKey(const ValueKey('section-tab:4')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('section-tab:4')));
        expect(selected, 4);
        expect(find.byType(FittedBox), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'appearance updates immediately, survives rebuild and does not touch data',
    (tester) async {
      final repo = DashboardRepository(
        LocalDatabase(':memory:')..set('automaticSync', false),
      );
      addTearDown(repo.dispose);
      repo.local.capture('workspace', {'goals': [], 'measurements': []});
      final raw = jsonEncode(repo.local.snapshot('workspace'));
      Widget app() =>
          DashboardApp(repo: repo, folder: '', backgroundEnabled: false);
      await tester.pumpWidget(app());
      repo.setUiPreference('appAppearance', 'dark');
      repo.setUiPreference('appTextScale', 1.2);
      repo.setUiPreference('appFont', 'NotoSans');
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold).first);
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(Theme.of(context).textTheme.bodyMedium!.fontFamily, 'NotoSans');
      expect(MediaQuery.textScalerOf(context).scale(10), closeTo(12, .01));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.dark,
      );
      repo.setUiPreference('appAppearance', 'pomodoro');
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first))
            .colorScheme
            .primary,
        dashboardTheme('pomodoro').colorScheme.primary,
      );
      expect(repo.pending, isEmpty);
      expect(jsonEncode(repo.local.snapshot('workspace')), raw);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'goal table merges computed values and keeps baseline and date in history',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DashboardRepository(LocalDatabase(':memory:'));
      addTearDown(repo.dispose);
      final goal = evaluateGoal(
        {'id': 'g', 'title': 'Клиенты', 'unit': 'чел.', 'target': 30},
        [
          {'value': 20, 'date': '2026-10-26'},
          {'value': 10, 'date': '2026-10-25'},
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GoalsTable(
                repo: repo,
                goals: [goal],
                edit: (_) {},
                measure: (_) {},
                child: (_) {},
                history: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Было'), findsNothing);
      expect(find.text('Прогресс'), findsNothing);
      expect(find.text('Дата замера'), findsNothing);
      expect(find.text('Шкала/характеристика сейчас'), findsOneWidget);
      expect(find.text('Предпочтительная мною шкала'), findsOneWidget);
      expect(find.textContaining('С начала: +10'), findsOneWidget);
      expect(find.textContaining('К предпочтительной: 50%'), findsOneWidget);
      expect(find.byTooltip(goalDeadlineHint), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
