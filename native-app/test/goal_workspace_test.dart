import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/goal_table.dart';
import 'package:indicators_work/goal_workspace.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/workspace_table.dart';

final sample = <Json>[
  {
    'id': 'a',
    'title': 'Родитель',
    'status': 'active',
    'unit': 'шт',
    'updatedAt': 'old',
  },
  {'id': 'b', 'title': 'Вложенная цель', 'parentId': 'a', 'status': 'ready'},
  {'id': 'c', 'title': 'Глубокая цель', 'parentId': 'b', 'status': 'planned'},
  {'id': 'd', 'title': 'Чужая ветвь', 'status': 'active'},
  {'id': 'e', 'title': 'Архивная цель', 'status': 'archived'},
  {'id': 'f', 'title': 'Подцель архива', 'parentId': 'e', 'status': 'active'},
];
DashboardRepository repository() => DashboardRepository(
  LocalDatabase(':memory:')
    ..set('serverId', 'test')
    ..set('automaticSync', false)
    ..capture('workspace', {'goals': sample, 'goalTrashVersion': 1}),
);
Widget page(DashboardRepository repo) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: ListenableBuilder(
        listenable: repo,
        builder: (_, _) => GoalsTable(
          repo: repo,
          goals: repo.entities('goals', 'goal'),
          edit: (_) {},
          measure: (_) {},
          child: (_) {},
          history: (_) {},
        ),
      ),
    ),
  ),
);

void main() {
  test('archive and trash boundaries exclude descendants and preserve raw hierarchy and WBS', () {
    final original = jsonEncode(sample);
    expect(filterGoalRows(sample).map((g) => g['id']), ['a', 'b', 'c', 'd']);
    expect(filterGoalRows(sample, mode: 'archived').map((g) => g['id']), [
      'e',
      'f',
    ]);
    expect(filterGoalRows(sample, mode: 'all'), hasLength(6));
    final filtered = filterGoalRows(sample, status: 'ready');
    expect(filtered.map((g) => g['id']), ['a', 'b']);
    expect(filtered.last['_sourceWbs'], '1.1');
    expect(filterGoalRows(sample, branchId: 'b').map((g) => g['id']), [
      'b',
      'c',
    ]);
    final trashed = [
      for (final g in sample)
        {...g, if (g['id'] == 'a') 'trashedAt': '2026-10-26T12:00:00Z'},
    ];
    expect(filterGoalRows(trashed, mode: 'all').map((g) => g['id']), [
      'd',
      'e',
      'f',
    ]);
    expect(filterGoalRows(trashed, mode: 'trash').map((g) => g['id']), [
      'a',
      'b',
      'c',
    ]);
    expect(filterGoalRows(trashed, mode: 'trash').last['_trashOwner'], 'a');
    expect(jsonEncode(sample), original);
  });
  test('trash coalesces unsent edits but never replaces an attempted command or measurements', () {
    final repo = repository();
    addTearDown(repo.dispose);
    repo.local.capture('workspace', {
      'goals': sample,
      'goalTrashVersion': 1,
      'measurements': [
        {
          'kind': 'goal',
          'targetId': 'a',
          'value': 0,
          'evidence': '  raw\n text  ',
        },
      ],
    });
    final original = jsonEncode(repo.cache('workspace')['measurements']);
    repo.editGoalField('a', 'trashedAt', '2026-10-26T12:00:00Z');
    expect(filterGoalRows(repo.entities('goals', 'goal')).map((g) => g['id']), [
      'd',
    ]);
    repo.editGoalField('a', 'trashedAt', null);
    expect(repo.pending, hasLength(1));
    expect(object(repo.pending.first['body'])['expectedUpdatedAt'], 'old');
    expect(jsonEncode(repo.cache('workspace')['measurements']), original);
    expect(filterGoalRows(repo.entities('goals', 'goal')), hasLength(4));
    final command = jsonEncode(repo.pending.single['body']);
    repo.local.attempted(repo.pending.single['id']);
    expect(
      () => repo.editGoalField('a', 'trashedAt', '2026-10-26T12:00:00Z'),
      throwsStateError,
    );
    expect(jsonEncode(repo.pending.single['body']), command);
  });
  testWidgets(
    'columns resize by a line and reorder directly without changing data',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = repository();
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceTable(
              repo: repo,
              viewKey: 'columns-test',
              grouping: false,
              items: const [],
              columns: const [
                WorkColumn('title', 'Цель'),
                WorkColumn('unit', 'Единица'),
                WorkColumn('target', 'Ориентир'),
              ],
              cell: (_, _, _) => const SizedBox(),
              value: (_, _) => '',
            ),
          ),
        ),
      );
      expect(find.text('Вид таблицы'), findsNothing);
      expect(find.text('Сохранить вид'), findsNothing);
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('column-resize:unit')),
        const Offset(45, 0),
      );
      await tester.pumpAndSettle();
      expect(
        object(object(repo.local.get('columns-test'))['widths'])['unit'],
        greaterThan(160),
      );
      final start = tester.getCenter(
        find.byKey(const ValueKey('column-drag:target')),
      );
      final end = tester.getCenter(
        find.byKey(const ValueKey('column-drag:title')),
      );
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(end);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(object(repo.local.get('columns-test'))['order'], [
        'target',
        'title',
        'unit',
      ]);
      expect(repo.pending, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'any nested goal opens alone with descendants, while back restores the table',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = repository();
      addTearDown(repo.dispose);
      await tester.pumpWidget(page(repo));
      await tester.pumpAndSettle();
      expect(find.text('Группировать верхние уровни'), findsNothing);
      final open = find.byKey(const ValueKey('goal-open:b'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('goal-focus:b')), findsOneWidget);
      expect(find.byKey(const ValueKey('goal-row:b')), findsOneWidget);
      expect(find.byKey(const ValueKey('goal-row:c')), findsOneWidget);
      expect(find.byKey(const ValueKey('goal-row:d')), findsNothing);
      expect(find.byKey(const ValueKey('goal-row:a')), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('goal-row:d')), findsOneWidget);
      expect(repo.pending, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'archive hides rows immediately and trash deletion can be restored',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = repository();
      addTearDown(repo.dispose);
      await tester.pumpWidget(page(repo));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('goal-menu:a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('В архив'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('goal-row:a')), findsNothing);
      expect(find.byKey(const ValueKey('goal-row:b')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('goal-filter-mode:current')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('В архиве').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('goal-row:a')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('goal-menu:a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить строку'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 подцелей'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('goal-row:a')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('goal-filter-mode:archived')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Корзина').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('goal-row:a')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('goal-menu:a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Восстановить из корзины'));
      await tester.pumpAndSettle();
      expect(repo.entities('goals', 'goal').first['trashedAt'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
