import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/goal_columns.dart';
import 'package:indicators_work/goal_notes.dart';
import 'package:indicators_work/goal_table.dart';
import 'package:indicators_work/goal_workspace.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/workspace_table.dart';

DashboardRepository repository() {
  final db = LocalDatabase(':memory:');
  db.set('serverId', 'owner');
  db.set('automaticSync', false);
  db.capture('workspace', {
    'goalGridVersion': 1,
    'goalNotesVersion': 1,
    'goals': [],
  });
  return DashboardRepository(db);
}

const noteColumn = {
  'id': 'notes',
  'title': 'Описание',
  'type': 'notes',
  'custom': true,
  'maxLength': 30000,
};
const baseGoal = {
  'id': 'g',
  'title': 'Домашнее хозяйство',
  'customValues': {'notes': 'Исходный текст'},
};

void main() {
  test('visible numbering follows filtering, sibling sorting and collapse without rewriting hierarchy', () {
    final source = <Json>[
      {'id': 'hidden', 'title': 'Архив', 'status': 'archived'},
      {'id': 'a', 'title': 'А', 'status': 'active'},
      {'id': 'child', 'title': 'Дочерняя', 'status': 'active', 'parentId': 'a'},
      {'id': 'b', 'title': 'Б', 'status': 'active'},
    ];
    final raw = jsonEncode(source), filtered = filterGoalRows(source);
    dynamic value(Json r, String key) => r['title'];
    final visible = arrangeTableRows(filtered, {}, value, {});
    expect(visible.map((r) => r['_rowNumber']), [1, 2, 3]);
    expect(visible.first['_wbs'], '2');
    final collapsed = arrangeTableRows(filtered, {}, value, {'a'});
    expect(collapsed.map((r) => r['id']), ['a', 'b']);
    expect(collapsed.map((r) => r['_rowNumber']), [1, 2]);
    final sorted = arrangeTableRows(
      filtered,
      {'sort': 'title', 'descending': true},
      value,
      {},
    );
    expect(sorted.map((r) => r['id']), ['b', 'a', 'child']);
    expect(sorted.map((r) => r['_rowNumber']), [1, 2, 3]);
    final search = arrangeTableRows(filtered, {'query': 'Б'}, value, {});
    expect(search.single['_rowNumber'], 1);
    expect(jsonEncode(source), raw);
  });

  test('notes links preserve fragments, reject credentials and never execute embedded markup', () {
    const raw =
        '  [Модель](https://example.com/model?q=one#section)\nhttps://example.com/model?q=one#section\nhttp://localhost:8787/#projects\nhttps://name:secret@example.com/\njavascript:alert(1)\n<script>text</script>  ';
    expect(notesLinks(raw).map((u) => u.toString()), [
      'https://example.com/model?q=one#section',
      'http://localhost:8787/#projects',
    ]);
    expect(raw.startsWith('  '), true);
  });

  testWidgets(
    'notes draft survives closing and keeps its original before when the server value changes',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = repository();
      addTearDown(repo.dispose);
      Widget page(Json goal) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: GoalCustomCell(repo: repo, goal: goal, column: noteColumn),
          ),
        ),
      );
      await tester.pumpWidget(page(baseGoal));
      await tester.tap(find.byKey(const ValueKey('goal-notes:g:notes')));
      await tester.pumpAndSettle();
      const raw =
          '  Полное описание\n\nВторая строка\nhttps://example.com/model#alpha  ';
      await tester.enterText(
        find.byKey(const ValueKey('goal-note-editor')),
        raw,
      );
      await tester.tap(find.byTooltip('Закрыть заметку'));
      await tester.pumpAndSettle();
      expect(object(repo.local.get('goalNote:owner:g:notes'))['text'], raw);
      expect(repo.pending, isEmpty);
      await tester.pumpWidget(
        page({
          ...baseGoal,
          'customValues': {'notes': 'Серверная правка'},
        }),
      );
      await tester.tap(find.byKey(const ValueKey('goal-notes:g:notes')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('goal-note-editor')))
            .controller!
            .text,
        raw,
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      final input = object(object(repo.pending.single['body'])['input']);
      expect(input['before'], 'Исходный текст');
      expect(input['value'], raw);
      expect(repo.local.get('goalNote:owner:g:notes'), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'oversized notes stay in the draft instead of being truncated or sent',
    (tester) async {
      final repo = repository();
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoalNotesEditor(
              repo: repo,
              goal: baseGoal,
              column: noteColumn,
            ),
          ),
        ),
      );
      final raw = 'я'.padRight(30001, 'я');
      await tester.enterText(
        find.byKey(const ValueKey('goal-note-editor')),
        raw,
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
      expect(find.byKey(const ValueKey('goal-note-error')), findsOneWidget);
      expect(object(repo.local.get('goalNote:owner:g:notes'))['text'], raw);
      expect(repo.pending, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'compact desktop headers keep functional controls and visible numbers',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = repository();
      addTearDown(repo.dispose);
      final goals = <Json>[
        {'id': 'archive', 'title': 'Архив', 'status': 'archived'},
        {'id': 'g', 'title': 'Видимая', 'status': 'active'},
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(
            body: SingleChildScrollView(
              child: GoalsTable(
                repo: repo,
                goals: goals,
                edit: (_) {},
                measure: (_) {},
                child: (_) {},
                history: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('1 · Видимая'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('column-rename:title'))).width,
        lessThanOrEqualTo(24),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('column-menu:title'))).width,
        lessThanOrEqualTo(24),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('goal-row:g'))).height,
        lessThanOrEqualTo(72),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('touch headers keep rename in one compact menu', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = repository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: SingleChildScrollView(
            child: GoalsTable(
              repo: repo,
              goals: const [baseGoal],
              edit: (_) {},
              measure: (_) {},
              child: (_) {},
              history: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('column-rename:title')), findsNothing);
    final menu = find.byKey(const ValueKey('column-menu:title'));
    expect(tester.getSize(menu).width, 44);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Переименовать'));
    await tester.pumpAndSettle();
    expect(find.text('Название столбца'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'Характеристика',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('notes remain usable with a phone keyboard and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final repo = repository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: GoalNotesCell(repo: repo, goal: baseGoal, column: noteColumn),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('goal-notes:g:notes')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('goal-note-editor')),
      'Текст\nhttps://example.com/',
    );
    await tester.pump();
    expect(find.text('Сохранить').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
