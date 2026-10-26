import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/grid_definitions.dart';
import 'package:indicators_work/workspace_table.dart';
import 'package:indicators_work/inline_cell.dart';
import 'package:indicators_work/adaptive_detail.dart';
import 'package:indicators_work/activity_status.dart';

void main() {
  test('search keeps ancestors and sorting preserves original WBS and raw hierarchy', () {
    final source = <Json>[
      {'id': 'root', 'name': 'A'},
      {'id': 'a', 'parentId': 'root', 'name': 'Zulu'},
      {'id': 'b', 'parentId': 'root', 'name': 'Alpha'},
      {'id': 'other', 'name': 'Other'},
    ];
    final raw = jsonEncode(source);
    dynamic value(Json r, String id) => id == '*' ? r['name'] : r[id];
    final sorted = arrangeTableRows(source, {'sort': 'name'}, value, {});
    expect(sorted.map((r) => r['id']), ['root', 'b', 'a', 'other']);
    expect(sorted[1]['_wbs'], '1.2');
    final searched = arrangeTableRows(
      source,
      {'query': 'zulu'},
      value,
      {'root'},
    );
    expect(searched.map((r) => r['id']), ['root', 'a']);
    expect(jsonEncode(source), raw);
  });
  test('undo adds an inverse cell command, keeps the original, and refuses a changed value', () {
    final db = LocalDatabase(':memory:')
      ..set('serverId', 'owner')
      ..set('automaticSync', false)
      ..capture('portfolio', {
        'tableEditing': 1,
        'tableDefinitions': defaultGridColumns,
        'projects': [
          {'id': 'p', 'name': '  До\nТекст  '},
        ],
      });
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    repo.editGridCell('projects', 'p', 'name', '  До\nТекст  ', 'После');
    final first = jsonEncode(repo.pending.single['body']);
    repo.undoGridCell();
    expect(repo.pending, hasLength(2));
    expect(jsonEncode(repo.pending.first['body']), first);
    expect(
      repo.entities('projects', 'project').single['name'],
      '  До\nТекст  ',
    );
    expect(repo.canUndoGrid, isFalse);
    repo.editGridCell('projects', 'p', 'name', '  До\nТекст  ', 'Моя правка');
    repo.gridCommand('editCells', {
      'table': 'projects',
      'id': 'p',
      'changes': [
        {'columnId': 'name', 'before': 'Моя правка', 'value': 'Поздняя правка'},
      ],
    });
    expect(repo.undoGridCell, throwsStateError);
    expect(
      repo.entities('projects', 'project').single['name'],
      'Поздняя правка',
    );
  });
  test(
    'goal edit retains the version from editor opening and supports null undo',
    () {
      final db = LocalDatabase(':memory:')
        ..set('serverId', 'owner')
        ..set('automaticSync', false)
        ..capture('workspace', {
          'goals': [
            {
              'id': 'g',
              'title': 'Цель',
              'status': 'active',
              'unit': 'шт',
              'updatedAt': 'old',
              'baseline': null,
            },
          ],
        });
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      final base = repo.entities('goals', 'goal').single;
      db.capture('workspace', {
        'goals': [
          {...base, 'updatedAt': 'new'},
        ],
      });
      repo.editGoalField('g', 'baseline', 0, expectedGoal: base);
      expect(object(repo.pending.single['body'])['expectedUpdatedAt'], 'old');
      expect(repo.entities('goals', 'goal').single['baseline'], 0);
      repo.undoGoalField();
      expect(repo.entities('goals', 'goal').single['baseline'], isNull);
      expect(repo.canUndoGoal, isFalse);
    },
  );
  testWidgets('inline Enter saves, Esc cancels and Tab reaches the next cell', (
    tester,
  ) async {
    String saved = 'До';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: InlineCell(
                  text: 'До',
                  label: 'Первое',
                  commit: (s) async {
                    saved = s;
                  },
                ),
              ),
              Expanded(
                child: InlineCell(
                  text: 'Далее',
                  label: 'Второе',
                  commit: (_) async {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('До'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Новый текст');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(saved, 'Новый текст');
    await tester.tap(find.text('До'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Не сохранять');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(saved, 'Новый текст');
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('До'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Tab save');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
    expect(saved, 'Tab save');
    final next = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Далее'),
    );
    expect(next.focusNode!.hasFocus, isTrue);
  });
  testWidgets(
    'detail stays centered and adapts to a narrow screen without losing typed text',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final input = TextEditingController();
      addTearDown(input.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAdaptiveDetail(
                  context,
                  builder: (_) => DetailFrame(
                    title: 'Детали',
                    body: TextField(controller: input, maxLines: 3),
                  ),
                ),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('adaptive-detail-panel')))
            .width,
        720,
      );
      expect(
        tester.getCenter(find.byKey(const ValueKey('adaptive-detail-panel'))),
        const Offset(700, 450),
      );
      await tester.enterText(find.byType(TextField), '  Исходный\nтекст  ');
      tester.view.physicalSize = const Size(360, 780);
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('adaptive-detail-panel')))
            .width,
        360,
      );
      expect(input.text, '  Исходный\nтекст  ');
      await tester.tap(find.byTooltip('Назад к списку'));
      await tester.pumpAndSettle();
      expect(find.text('Открыть'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('status distinguishes local queue, conflict and confirmed sync', (
    tester,
  ) async {
    final db = LocalDatabase(':memory:')
      ..set('serverId', 'owner')
      ..set('automaticSync', false);
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    db.set('lastSyncAt', '2026-10-25T07:00:00Z');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ActivityStatus(repo: repo)),
      ),
    );
    expect(find.text('Синхронизировано · 12:00'), findsOneWidget);
    repo.nativeSave('workspace', 'saveGoal', {'title': 'Цель'}, 'goal:g');
    await tester.pump();
    expect(find.textContaining('ожидает отправки: 1'), findsOneWidget);
    db.conflict(repo.pending.single['id'], 'Конфликт');
    repo.notifyListeners();
    await tester.pump();
    expect(find.textContaining('Не отправлено'), findsOneWidget);
    expect(find.text('Синхронизировано · 12:00'), findsNothing);
  });
  testWidgets(
    'table keeps headers and first column fixed; search survives remount without view settings',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DashboardRepository(LocalDatabase(':memory:'));
      addTearDown(repo.dispose);
      final items = <Json>[
        for (var i = 0; i < 16; i++)
          {'id': 'r$i', 'title': 'Строка $i', 'value': 'Значение $i'},
      ];
      Widget app() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkspaceTable(
              repo: repo,
              viewKey: 'test-view',
              columns: const [
                WorkColumn('title', 'Имя', width: 220),
                WorkColumn('value', 'Значение', width: 500),
                WorkColumn('extra', 'Дополнительно', width: 500),
              ],
              items: items,
              value: (r, c) => c == '*' ? r['title'] : r[c],
              cell: (_, r, c) =>
                  Text((r[c.id] ?? 'Дополнительный текст').toString()),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final first = find.text('Строка 0'),
          header = find.byKey(const ValueKey('workspace-sticky-header'));
      final x = tester.getTopLeft(first).dx, y = tester.getTopLeft(header).dy;
      final footer = find.byType(Scrollbar).last;
      await tester.ensureVisible(footer);
      await tester.pumpAndSettle();
      final scroller = find.descendant(
        of: footer,
        matching: find.byType(SingleChildScrollView),
      );
      await tester.drag(scroller, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(first).dx, x);
      final inner = find.byType(Scrollbar).first;
      await tester.drag(
        find
            .descendant(of: inner, matching: find.byType(SingleChildScrollView))
            .first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(header).dy, y);
      await tester.enterText(
        find.widgetWithText(TextField, 'Поиск по таблице'),
        'Строка 12',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('workspace-row:r12')),
          matching: find.text('Строка 12'),
        ),
        findsOneWidget,
      );
      expect(find.text('Строка 0'), findsNothing);
      expect(find.text('Вид таблицы'), findsNothing);
      expect(find.text('Сохранить вид'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('workspace-row:r12')),
          matching: find.text('Строка 12'),
        ),
        findsOneWidget,
      );
      expect(object(repo.local.get('test-view'))['query'], 'Строка 12');
      expect(repo.pending, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
