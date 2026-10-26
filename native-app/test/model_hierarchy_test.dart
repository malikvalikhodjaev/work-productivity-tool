import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/grid_definitions.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/model_hierarchy.dart';
import 'package:indicators_work/modeling_workspace.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/workspace_table.dart';

void main() {
  final project = <String, dynamic>{
    'id': 'p',
    'name': 'Проект',
    'status': 'active',
    'phase': 'pre_operation',
    'zones': [
      {'id': 'z', 'title': 'Зона'},
    ],
    'copyVersion': 'source-version',
  };
  final a = <String, dynamic>{
    'id': 'a',
    'projectId': 'p',
    'zoneId': 'z',
    'parentId': null,
    'typeName': 'Система',
    'uniqueName': 'Моя система',
    'state': 'empty',
    'description': '  Моя запись\nВторая строка  ',
  };
  final b = <String, dynamic>{
    ...a,
    'id': 'b',
    'parentId': 'a',
    'uniqueName': 'Подсистема',
  };
  final c = <String, dynamic>{...a, 'id': 'c', 'uniqueName': 'Другая система'};
  final template = <String, dynamic>{
    'id': 't',
    'version': 'v1',
    'title': 'Набор',
    'capturedAt': '2026-10-19',
    'areas': [
      {'id': 'z', 'title': 'Зона'},
    ],
    'sources': {},
    'alphas': [
      {
        'sourceId': 's',
        'areaId': 'z',
        'parentId': null,
        'typeName': 'Система',
        'states': [
          {
            'title': 'Описана',
            'sourceId': 'state',
            'questions': [
              {'sourceId': 'question', 'text': 'Где граница?'},
            ],
          },
        ],
      },
      {
        'sourceId': 'child',
        'parentId': 's',
        'areaId': 'z',
        'typeName': 'Подсистема',
      },
    ],
  };
  DashboardRepository open(String file, {bool seed = false}) {
    final db = LocalDatabase(file);
    if (seed) {
      db.set('serverId', 'owner');
      db.set('automaticSync', false);
      db.capture('portfolio', {
        'tableEditing': 1,
        'hierarchyEditing': 1,
        'tableDefinitions': defaultGridColumns,
        'projectTemplates': [template],
        'projects': [project],
        'alphas': [a, b, c],
      });
    }
    return DashboardRepository(db);
  }

  test(
    'WBS supports deep nesting, collapsing and moving while preserving text',
    () {
      final original = [
        a,
        b,
        {...a, 'id': 'd', 'parentId': 'b', 'uniqueName': 'Часть'},
        c,
      ];
      expect(hierarchyRows(original).map((r) => r['_wbs']), [
        '1',
        '1.1',
        '1.1.1',
        '2',
      ]);
      expect(hierarchyRows(original, collapsed: {'a'}).map((r) => r['_wbs']), [
        '1',
        '2',
      ]);
      final moved = relocateAlpha(original, {'id': 'b', 'parentId': 'c'});
      expect(hierarchyRows(moved).map((r) => r['_wbs']), [
        '1',
        '2',
        '2.1',
        '2.1.1',
      ]);
      expect(moved.first['description'], a['description']);
      expect(
        () => relocateAlpha(original, {'id': 'a', 'parentId': 'd'}),
        throwsStateError,
      );
      expect(
        hierarchySignature(original),
        '[["a",null,null,"z"],["b","a",null,"z"],["c",null,null,"z"],["d","b",null,"z"]]',
      );
    },
  );
  test('Offline copy and edits survive restart; an accepted copy snapshot does not duplicate or reset rows', () {
    final folder = Directory.systemTemp.createTempSync('iw-template-local-'),
        file = '${folder.path}/local.sqlite';
    var repo = open(file, seed: true);
    repo.gridCommand('copyProject', {
      'clientId': 'new-project',
      'name': 'Новая структура',
      'templateId': 't',
      'expectedVersion': 'v1',
      'alphaIds': {'s': 'root', 'child': 'child'},
      'areaIds': ['z'],
      'localDefinition': template,
    });
    repo.gridCommand('editCells', {
      'table': 'alphas',
      'id': 'root',
      'changes': [
        {'columnId': 'uniqueName', 'before': '', 'value': 'Мой новый объект'},
      ],
    });
    final pending = repo
        .entities('alphas', 'alpha')
        .where((r) => r['projectId'] == 'new-project')
        .toList();
    repo.gridCommand('moveAlpha', {
      'id': 'child',
      'parentId': null,
      'expectedHierarchy': hierarchySignature(pending),
    });
    repo.dispose();
    repo = open(file);
    final copied = repo
        .entities('alphas', 'alpha')
        .where((r) => r['projectId'] == 'new-project')
        .toList();
    expect(copied.first['uniqueName'], 'Мой новый объект');
    expect(copied.last['parentId'], null);
    expect(copied.first['state'], 'empty');
    expect(copied.first['filledDate'], null);
    expect(repo.entities('projects', 'project'), hasLength(2));
    expect(rows(copied.first['templateStates']).single['title'], 'Описана');
    final cached = repo.cache('portfolio');
    repo.local.capture('portfolio', {
      ...cached,
      'projects': [
        project,
        {'id': 'new-project', 'name': 'Серверная копия'},
      ],
      'alphas': [a, b, c, ...copied],
    });
    expect(repo.entities('projects', 'project'), hasLength(2));
    expect(
      repo
          .entities('alphas', 'alpha')
          .where((r) => r['projectId'] == 'new-project'),
      hasLength(2),
    );
    repo.dispose();
  });
  test(
    'A later offline card edit follows the queued WBS move after restart',
    () {
      final folder = Directory.systemTemp.createTempSync('iw-wbs-order-'),
          file = '${folder.path}/local.sqlite';
      var repo = open(file, seed: true);
      repo.gridCommand('moveAlpha', {
        'id': 'b',
        'parentId': 'c',
        'expectedHierarchy': hierarchySignature([a, b, c]),
      });
      final moved = repo
          .entities('alphas', 'alpha')
          .singleWhere((r) => r['id'] == 'b');
      expect(moved['parentId'], 'c');
      final cardEdit = {
        ...moved,
        'parentId': 'a',
        'description': '  Исправил\nПосле переноса  ',
      };
      repo.nativeSave(
        'portfolio',
        'updateAlpha',
        cardEdit,
        'alpha:b',
        draft: cardEdit,
      );
      repo.dispose();
      repo = open(file);
      final restored = repo
          .entities('alphas', 'alpha')
          .singleWhere((r) => r['id'] == 'b');
      expect(restored['parentId'], 'a');
      expect(restored['description'], '  Исправил\nПосле переноса  ');
      expect(repo.pending, hasLength(2));
      repo.dispose();
    },
  );
  testWidgets(
    'Projects switch to board while the selected model stays a table; branches can collapse',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('iw-project-board-'),
          repo = open('${folder.path}/local.sqlite', seed: true);
      repo.local.set('modelerProjectId', 'p');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ModelingWorkspace(
                repo: repo,
                createProject: () async {},
                editProject: (_) async {},
                editAlpha: (_, _) async {},
                createInZone: (_, _) async {},
                createChild: (_, _) async {},
                focusAlpha: (_) async {},
                linkSystem: (_) async {},
                characteristics: (_) => const SizedBox(),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(WorkspaceTable), findsNWidgets(2));
      await tester.tap(find.text('Доска'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceTable), findsOneWidget);
      expect(repo.local.get('projectView'), 'board');
      await tester.ensureVisible(
        find.byKey(const ValueKey('model-tree-toggle:alpha:a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('model-tree-toggle:alpha:a')));
      await tester.pump();
      expect(find.textContaining('Подсистема'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
}
