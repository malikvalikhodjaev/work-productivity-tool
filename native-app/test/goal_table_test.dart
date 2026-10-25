import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/goal_progress.dart';
import 'package:indicators_work/goal_table.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';

Widget page(
  DashboardRepository repo,
  List<Json> goals, {
  void Function(Json)? edit,
  void Function(Json)? measure,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: GoalsTable(
        repo: repo,
        goals: goals,
        edit: edit ?? (_) {},
        measure: measure ?? (_) {},
        child: (_) {},
        history: (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'branches collapse independently, persist and preserve source data and WBS',
    (tester) async {
      final repo = DashboardRepository(LocalDatabase(':memory:'));
      addTearDown(repo.dispose);
      final goals = <Json>[
        {'id': 'a', 'title': 'Родитель', 'status': 'active'},
        {'id': 'b', 'parentId': 'a', 'title': 'Ребёнок', 'status': 'active'},
        {'id': 'c', 'parentId': 'b', 'title': 'Внук', 'status': 'active'},
        {'id': 'd', 'title': 'Другая цель', 'status': 'active'},
      ];
      repo.local.capture('workspace', {'goals': goals});
      final before = jsonEncode(repo.local.snapshot('workspace'));
      await tester.pumpWidget(page(repo, goals));
      expect(find.text('1.1.1 · Внук'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('goal-toggle:b')));
      await tester.tap(find.byKey(const ValueKey('goal-toggle:b')));
      await tester.pump();
      expect(find.text('1.1 · Ребёнок'), findsOneWidget);
      expect(find.text('1.1.1 · Внук'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('goal-toggle:a')));
      await tester.tap(find.byKey(const ValueKey('goal-toggle:a')));
      await tester.pump();
      expect(find.text('1.1 · Ребёнок'), findsNothing);
      expect(find.text('2 · Другая цель'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page(repo, goals));
      expect(find.text('1.1 · Ребёнок'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('goal-toggle:a')));
      await tester.tap(find.byKey(const ValueKey('goal-toggle:a')));
      await tester.pump();
      expect(find.text('1.1 · Ребёнок'), findsOneWidget);
      expect(find.text('1.1.1 · Внук'), findsNothing);
      expect(jsonEncode(repo.local.snapshot('workspace')), before);
      expect(repo.pending, isEmpty);
    },
  );
  testWidgets('Fill opens the correct input, while a real zero remains zero', (
    tester,
  ) async {
    final repo = DashboardRepository(LocalDatabase(':memory:'));
    addTearDown(repo.dispose);
    String? action;
    final goals = <Json>[
      evaluateGoal({
        'id': 'g',
        'title': 'Показатель',
        'baseline': 0,
        'status': 'active',
      }, []),
    ];
    await tester.pumpWidget(
      page(
        repo,
        goals,
        edit: (_) => action = 'edit',
        measure: (_) => action = 'measure',
      ),
    );
    expect(find.text('No Data'), findsNothing);
    expect(goalNumber(null), 'Заполнить');
    expect(goalNumber(0), '0');
    final baseline = find.descendant(
      of: find.byKey(const ValueKey('goal-cell:baseline:g')),
      matching: find.byType(TextButton),
    );
    await tester.ensureVisible(baseline);
    await tester.tap(baseline);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('goal-cell:baseline:g')),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
    expect(action, isNull);
    final current = find.descendant(
      of: find.byKey(const ValueKey('goal-cell:current:g')),
      matching: find.byType(TextButton),
    );
    await tester.ensureVisible(current);
    await tester.tap(current);
    expect(action, 'measure');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'narrow enlarged text scrolls as a table without shrinking or ellipses',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DashboardRepository(LocalDatabase(':memory:'));
      addTearDown(repo.dispose);
      final title = List.filled(12, 'Длинное название цели').join(' ');
      final goal = evaluateGoal(
        {
          'id': 'g',
          'title': title,
          'status': 'active',
          'baseline': 10,
          'target': 30,
          'unit': 'UZS / месяц',
        },
        [
          {'value': 20, 'date': '2026-10-25'},
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
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('1 · $title'));
      expect(text.maxLines, null);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(find.byType(FittedBox), findsNothing);
      final history = find.byKey(const ValueKey('goal-history:g'));
      await tester.ensureVisible(history);
      await tester.pumpAndSettle();
      expect(history.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
