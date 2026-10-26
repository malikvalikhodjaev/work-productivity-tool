import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/goal_change_scale.dart';
import 'package:indicators_work/goal_progress.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/workspace_table.dart';

void main() {
  test('scale follows baseline-to-preferred direction, supports zero and retains overshoot', () {
    expect(goalScaleRatio({'baseline': 0, 'current': 5, 'target': 10}), .5);
    expect(
      goalScaleRatio({'comparisonBaseline': 20, 'current': 10, 'target': 5}),
      closeTo(2 / 3, .000001),
    );
    expect(goalScaleRatio({'baseline': 10, 'current': 25, 'target': 20}), 1.5);
    expect(goalScaleRatio({'baseline': 10, 'current': 5, 'target': 20}), -.5);
    expect(goalScaleRatio({'baseline': 0, 'current': 0, 'target': 10}), 0);
    expect(goalScaleRatio({'baseline': 5, 'current': 5, 'target': 5}), isNull);
    expect(goalScaleRatio({'current': 5, 'target': 10}), isNull);
  });
  testWidgets(
    'decreasing characteristic places marker correctly without changing measurements',
    (tester) async {
      final goal = evaluateGoal(
        {
          'id': 'g',
          'baseline': 20,
          'target': 5,
          'direction': 'down',
          'unit': 'ч',
        },
        [
          {'value': 10},
        ],
      );
      final raw = jsonEncode(goal);
      var measured = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: GoalChangeScale(
                goal: goal,
                measure: () => measured = true,
                configure: () {},
              ),
            ),
          ),
        ),
      );
      final paint =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('goal-scale-marker:g')),
                  )
                  .painter!
              as GoalScalePainter;
      expect(paint.position, closeTo(2 / 3, .000001));
      expect(find.text('Сейчас: 10'), findsOneWidget);
      expect(find.text('67%'), findsOneWidget);
      expect(jsonEncode(goal), raw);
      expect(measured, isFalse);
      await tester.tap(find.text('Сейчас: 10'));
      expect(measured, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unknown scale asks for input and never draws an invented percentage',
    (tester) async {
      var measure = 0, configure = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: GoalChangeScale(
                goal: const {'id': 'empty'},
                measure: () => measure++,
                configure: () => configure++,
              ),
            ),
          ),
        ),
      );
      expect(
        find
            .byType(CustomPaint)
            .evaluate()
            .where(
              (e) => (e.widget as CustomPaint).painter is GoalScalePainter,
            ),
        isEmpty,
      );
      expect(find.text('0%'), findsNothing);
      await tester.tap(find.text('Записать шкалу'));
      expect(measure, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: GoalChangeScale(
                goal: const {'id': 'partial', 'baseline': 0, 'current': 1},
                measure: () => measure++,
                configure: () => configure++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Предпочтительное: Заполнить'));
      expect(configure, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'narrow enlarged scale wraps text and clamps only the marker for an exceeded target',
    (tester) async {
      final goal = evaluateGoal(
        {
          'id': 'over',
          'baseline': 10,
          'target': 20,
          'unit': 'длинная единица измерения',
        },
        [
          {'value': 25},
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: SizedBox(
                    width: 100,
                    child: GoalChangeScale(
                      goal: goal,
                      measure: () {},
                      configure: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final paint =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('goal-scale-marker:over')),
                  )
                  .painter!
              as GoalScalePainter;
      expect(paint.position, 1);
      expect(find.text('150% · достигнуто'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'clean grid uses neutral cells in light and dark and preserves presentation-only selection',
    (tester) async {
      final repo = DashboardRepository(LocalDatabase(':memory:'));
      addTearDown(repo.dispose);
      final source = <Json>[
        {'id': 'root', 'title': 'Родитель'},
        {'id': 'child', 'parentId': 'root', 'title': 'Подстрока'},
      ];
      final raw = jsonEncode(source);
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.green,
                brightness: brightness,
              ),
            ),
            home: Scaffold(
              body: WorkspaceTable(
                repo: repo,
                viewKey: 'clean-test',
                cleanGrid: true,
                grouping: false,
                columns: const [
                  WorkColumn('title', 'Индикатор'),
                  WorkColumn('system', 'Система'),
                ],
                items: source,
                value: (r, c) => r['title'],
                cell: (_, r, c) => Text(
                  c.id == 'title' ? r['title'].toString() : 'Моё хозяйство',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final child = tester.widget<Container>(
          find.byKey(const ValueKey('workspace-row:child')),
        );
        expect(
          (child.decoration! as BoxDecoration).color,
          brightness == Brightness.light
              ? Colors.white
              : const Color(0xff202225),
        );
        await tester.tap(find.text('Родитель'));
        await tester.pump();
        expect(repo.local.get('clean-test:selection'), 'root');
        expect(jsonEncode(source), raw);
        expect(repo.pending, isEmpty);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
