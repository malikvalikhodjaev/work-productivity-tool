import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/goal_table.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/table_progress.dart';
import 'package:indicators_work/workspace_table.dart';

DashboardRepository repository() => DashboardRepository(
  LocalDatabase(':memory:')
    ..set('serverId', 'test')
    ..set('automaticSync', false)
    ..capture('workspace', {
      'goalGridVersion': 1,
      'goalTrashVersion': 1,
      'goals': [
        {
          'id': 'g',
          'title': 'Расходы хозяйства',
          'unit': 'UZS / месяц',
          'direction': 'down',
          'status': 'active',
          'updatedAt': 'base',
          'physicalSystem': 'Моё домашнее хозяйство',
        },
      ],
    }),
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
  testWidgets(
    'narrow table keeps indicator readable and scrolls columns instead of squeezing its title',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = repository();
      addTearDown(repo.dispose);
      await tester.pumpWidget(page(repo));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('goal-row:g'));
      expect(tester.getRect(row).height, lessThan(200));
      expect(
        find.byKey(const ValueKey('goal-menu:g')).hitTestable(),
        findsOneWidget,
      );
      final source = jsonEncode(repo.entities('goals', 'goal'));
      final header = find.byKey(const ValueKey('workspace-sticky-header'));
      await tester.dragFrom(tester.getCenter(header), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(jsonEncode(repo.entities('goals', 'goal')), source);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'remove and restore columns without an extra change column or loss of raw custom data',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = repository();
      addTearDown(repo.dispose);
      final custom = uuid.v4();
      repo.goalGridCommand('createGoalColumn', {
        'id': custom,
        'title': 'Мой контекст',
        'type': 'text',
      });
      repo.editGoalCell('g', custom, null, '  исходный\nтекст  ');
      await tester.pumpWidget(page(repo));
      await tester.pumpAndSettle();
      WorkspaceTable table() =>
          tester.widget<WorkspaceTable>(find.byType(WorkspaceTable));
      expect(table().columns.any((c) => c.id == 'delta'), isFalse);
      await tester.tap(
        find.byKey(const ValueKey('column-menu:physicalSystem')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('column-remove:physicalSystem')),
      );
      await tester.pumpAndSettle();
      expect(table().columns.any((c) => c.id == 'physicalSystem'), isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page(repo));
      await tester.pumpAndSettle();
      expect(table().columns.any((c) => c.id == 'physicalSystem'), isFalse);
      await tester.tap(find.byKey(const ValueKey('table-add-column')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Физическая система'));
      await tester.pumpAndSettle();
      expect(table().columns.any((c) => c.id == 'physicalSystem'), isTrue);
      await tester.ensureVisible(find.byKey(ValueKey('column-menu:$custom')));
      await tester.tap(find.byKey(ValueKey('column-menu:$custom')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('column-remove:$custom')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Убрать'));
      await tester.pumpAndSettle();
      expect(table().columns.any((c) => c.id == custom), isFalse);
      expect(
        object(repo.entities('goals', 'goal').single['customValues'])[custom],
        '  исходный\nтекст  ',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('table-add-column')),
      );
      await tester.tap(find.byKey(const ValueKey('table-add-column')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Мой контекст'));
      await tester.pumpAndSettle();
      expect(table().columns.any((c) => c.id == custom), isTrue);
      expect(
        object(repo.entities('goals', 'goal').single['customValues'])[custom],
        '  исходный\nтекст  ',
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('offline column definitions and exact custom cells persist in projections without rewriting commands', () {
    final repo = repository();
    addTearDown(repo.dispose);
    final id = uuid.v4();
    repo.goalGridCommand('createGoalColumn', {
      'id': id,
      'title': 'Мой столбец',
      'type': 'text',
    });
    final first = jsonEncode(repo.pending.first['body']);
    repo.editGoalCell('g', id, null, '  исходный\nтекст  ');
    expect(repo.goalColumns().last['id'], id);
    expect(
      object(repo.entities('goals', 'goal').single['customValues'])[id],
      '  исходный\nтекст  ',
    );
    repo.undoGoalField();
    expect(
      object(repo.entities('goals', 'goal').single['customValues'])[id],
      isNull,
    );
    expect(repo.pending, hasLength(3));
    expect(jsonEncode(repo.pending.first['body']), first);
    repo.editGoalField('g', 'physicalSystem', '  Личное\nхозяйство  ');
    expect(
      repo.entities('goals', 'goal').single['physicalSystem'],
      '  Личное\nхозяйство  ',
    );
  });
  test(
    'fresh remote custom values remain visible beneath an unrelated goal draft',
    () {
      final repo = repository();
      addTearDown(repo.dispose);
      final id = uuid.v4();
      repo.editGoalField('g', 'physicalSystem', '  Система владельца  ');
      final goal = object(repo.cache('workspace')['goals'].first);
      repo.local.capture('workspace', {
        'goalGridVersion': 1,
        'goals': [
          {
            ...goal,
            'customValues': {id: 'Свежее значение'},
          },
        ],
      });
      expect(
        object(repo.entities('goals', 'goal').single['customValues'])[id],
        'Свежее значение',
      );
      expect(
        repo.entities('goals', 'goal').single['physicalSystem'],
        '  Система владельца  ',
      );
    },
  );
  testWidgets(
    'all headers have names, menu sits beside indicator and pencil renames without changing its field ID',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = repository();
      addTearDown(repo.dispose);
      await tester.pumpWidget(page(repo));
      await tester.pumpAndSettle();
      final table = tester.widget<WorkspaceTable>(find.byType(WorkspaceTable));
      expect(table.columns.every((c) => c.title.trim().isNotEmpty), isTrue);
      expect(table.columns.any((c) => c.id == '_actions'), isFalse);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('column-cell:title')).last,
          matching: find.byKey(const ValueKey('goal-menu:g')),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('goal-cell:physicalSystem:g')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('column-rename:title')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Название'),
        'Моя характеристика',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.goalColumns().first['title'], 'Моя характеристика');
      expect(repo.goalColumns().first['id'], 'title');
      expect(
        repo.entities('goals', 'goal').single['title'],
        'Расходы хозяйства',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'plus creates a typed column and its raw multiline value stays editable',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = repository();
      addTearDown(repo.dispose);
      await tester.pumpWidget(page(repo));
      await tester.pumpAndSettle();
      final add = find.byKey(const ValueKey('table-add-column'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Название'),
        'Контекст',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();
      final id = repo.goalColumns().last['id'];
      final cell = find.byKey(ValueKey('goal-custom:g:$id'));
      await tester.ensureVisible(cell);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: cell, matching: find.byType(TextButton)).first,
      );
      await tester.pump();
      await tester.enterText(
        find.descendant(of: cell, matching: find.byType(TextField)),
        '  Разобраться\nс расходами  ',
      );
      await tester.tap(
        find.descendant(
          of: cell,
          matching: find.widgetWithText(TextButton, 'Сохранить'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        object(repo.entities('goals', 'goal').single['customValues'])[id],
        '  Разобраться\nс расходами  ',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'week progress shows counts, percentages and overflow without inventing a zero-denominator percentage',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TableProgress(done: 4, planned: 10),
                TableProgress(done: 12, planned: 10),
                TableProgress(done: 0, planned: 0),
              ],
            ),
          ),
        ),
      );
      expect(find.text('4 / 10 · 40%'), findsOneWidget);
      expect(find.text('12 / 10 · 120%'), findsOneWidget);
      expect(find.text('0 / 0'), findsOneWidget);
      final bars = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .toList();
      expect(bars.map((b) => b.value), [.4, 1]);
      expect(tester.takeException(), isNull);
    },
  );
}
