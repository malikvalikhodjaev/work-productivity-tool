import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/goal_progress.dart';
import 'package:indicators_work/goal_table.dart';
import 'package:indicators_work/grid_definitions.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/model_hierarchy.dart';
import 'package:indicators_work/model_link.dart';
import 'package:indicators_work/project_models_table.dart';
import 'package:indicators_work/repository.dart';

const voice = '/api/inbox/abcdef12-1234-4321-abcd-123456789abc/audio';
void main() {
  test('voice uses the actual protected route and optional Windows WAV without leaking authorization', () async {
    final db = LocalDatabase(':memory:')
      ..set('baseUrl', 'https://owner.example');
    db.set('serverAuth', {
      'origin': 'https://owner.example',
      'authorization': 'Basic test-scope',
    });
    final calls = <Uri>[];
    final repo = DashboardRepository(
      db,
      client: MockClient((r) async {
        calls.add(r.url);
        expect(r.headers['authorization'], 'Basic test-scope');
        expect(r.headers['origin'], 'https://owner.example');
        return http.Response.bytes(
          [79, 103, 103, 83],
          200,
          headers: {'content-type': r.url.hasQuery ? 'audio/wav' : 'audio/ogg'},
        );
      }),
    );
    addTearDown(repo.dispose);
    expect(await repo.inboxAudio(voice), [79, 103, 103, 83]);
    await repo.inboxAudio(voice, compatible: true);
    expect(calls.last.queryParameters, {'format': 'wav'});
    for (final route in [
      'https://other.example$voice',
      '/api/inbox/audio/not-an-id',
      '$voice?other=1',
      '$voice#fragment',
      '/api/inbox/../../writing',
    ]) {
      await expectLater(repo.inboxAudio(route), throwsArgumentError);
    }
    expect(calls, hasLength(2));
  });
  test(
    'voice rejects HTML and redirects and distinguishes permission errors',
    () async {
      for (final status in [200, 302, 401, 404]) {
        final repo = DashboardRepository(
          LocalDatabase(':memory:')..set('baseUrl', 'https://owner.example'),
          client: MockClient(
            (_) async => http.Response(
              '<html>unavailable</html>',
              status,
              headers: {
                'content-type': 'text/html',
                'location': 'https://other.example',
              },
            ),
          ),
        );
        await expectLater(
          repo.inboxAudio(voice),
          throwsA(
            status == 401 || status == 404
                ? isA<ApiFailure>()
                : isA<StateError>(),
          ),
        );
        repo.dispose();
      }
    },
  );
  test('mixed project and alpha hierarchy is a projection with stable independent IDs', () {
    final projects = <Json>[
      {'id': 'p', 'name': 'Проект'},
      {'id': 'sub', 'parentId': 'p', 'name': 'Подпроект'},
    ];
    final alphas = <Json>[
      {'id': 'a', 'projectId': 'p', 'uniqueName': 'Модель'},
      {'id': 'b', 'projectId': 'p', 'parentId': 'a', 'uniqueName': 'Подальфа'},
    ];
    final raw = jsonEncode([projects, alphas]);
    final rows = hierarchyRows(projectModelRows(projects, alphas));
    expect(rows.first['id'], 'project:p');
    expect(rows.first['_hasChildren'], true);
    expect(rows.firstWhere((r) => r['id'] == 'alpha:b')['_depth'], 2);
    expect(jsonEncode([projects, alphas]), raw);
    expect(modelLinkUri('javascript:alert(1)'), isNull);
    expect(modelLinkUri('https://user:secret@example.org/model'), isNull);
    expect(modelLinkUri('https://example.org/model#alpha')!.fragment, 'alpha');
  });
  testWidgets(
    'mixed table collapses branches and saves exact URL by the alpha cell command',
    (tester) async {
      tester.view.physicalSize = const Size(1700, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final projects = <Json>[
        {'id': 'p', 'name': 'Проект', 'status': 'active'},
      ];
      final alphas = <Json>[
        {
          'id': 'a',
          'projectId': 'p',
          'uniqueName': 'Модель',
          'state': 'empty',
          'parentId': null,
          'modelUrl': null,
        },
      ];
      final db = LocalDatabase(':memory:')
        ..set('serverId', 'owner')
        ..set('automaticSync', false)
        ..capture('portfolio', {
          'tableEditing': 1,
          'tableDefinitions': defaultGridColumns,
          'projects': projects,
          'alphas': alphas,
        });
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProjectModelsTable(
                repo: repo,
                projects: projects,
                alphas: alphas,
                openProject: (_) {},
                openAlpha: (_) {},
                addAlpha: (_) {},
                addChild: (_) {},
              ),
            ),
          ),
        ),
      );
      final toggle = find.byKey(const ValueKey('model-tree-toggle:project:p'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pump();
      expect(find.text('1.1 · Модель'), findsNothing);
      await tester.tap(toggle);
      await tester.pump();
      final cell = find.byKey(
        const ValueKey('model-tree-cell:alpha:a:modelUrl'),
      );
      await tester.ensureVisible(cell);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: cell, matching: find.byType(TextButton)).first,
      );
      await tester.pump();
      final field = find.descendant(of: cell, matching: find.byType(TextField));
      await tester.enterText(field, 'https://example.org/model#raw');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repo.pending, hasLength(1));
      final input = object(object(repo.pending.single['body'])['input']);
      expect(input['table'], 'alphas');
      expect(input['id'], 'a');
      expect(input['changes'], [
        {
          'columnId': 'modelUrl',
          'before': null,
          'value': 'https://example.org/model#raw',
        },
      ]);
      expect(alphas.single['modelUrl'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('goal status list saves a stage while keeping the linked work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final goal = <String, dynamic>{
      'id': 'g',
      'title': 'Цель',
      'status': 'active',
      'workRef': 'work:linked',
      'unit': 'шт.',
    };
    final db = LocalDatabase(':memory:')
      ..set('serverId', 'owner')
      ..set('automaticSync', false)
      ..capture('workspace', {
        'goals': [goal],
      });
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GoalsTable(
              repo: repo,
              goals: [evaluateGoal(goal, [])],
              edit: (_) {},
              measure: (_) {},
              child: (_) {},
              history: (_) {},
            ),
          ),
        ),
      ),
    );
    final status = find.byKey(const ValueKey('goal-status:g:active'));
    await tester.ensureVisible(status);
    await tester.pumpAndSettle();
    await tester.tap(status);
    await tester.pumpAndSettle();
    await tester.tap(find.text('В эксплуатации').last);
    await tester.pumpAndSettle();
    final input = object(object(repo.pending.single['body'])['input']);
    expect(input['status'], 'operation');
    expect(input['workRef'], 'work:linked');
    expect(tester.takeException(), isNull);
  });
}
