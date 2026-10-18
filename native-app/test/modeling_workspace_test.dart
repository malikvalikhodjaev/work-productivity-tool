import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/modeler.dart';
import 'package:indicators_work/modeling_workspace.dart';
import 'package:indicators_work/repository.dart';

void main() {
  final project = <String, dynamic>{
    'id': 'house',
    'name': 'Продажа дома',
    'status': 'active',
    'phase': 'pre_operation',
    'zones': [
      {'id': 'customers', 'title': 'Покупатели', 'typeName': 'Клиентура'},
    ],
  };
  final root = <String, dynamic>{
    'id': 'buyers',
    'projectId': 'house',
    'zoneId': 'customers',
    'parentId': null,
    'typeName': 'Клиентура',
    'uniqueName': 'Покупатели дома',
    'state': 'verified',
    'description': '  Модель\nУточнение  ',
    'criteria': 'Потребности проверены',
    'evidence': 'Запись разговора',
    'filledDate': '2026-10-18',
  };

  test(
    'filled slots do not imply verified coverage; a child keeps its zone open',
    () {
      final working = {
        ...root,
        'state': 'described',
        'criteria': '',
        'evidence': '',
      };
      final pending = modelProject(project, [working]);
      expect(object(pending['summary'])['filled'], 1);
      expect(object(pending['summary'])['gaps'], 1);
      expect(rows(pending['zones']).single['covered'], false);
      final verified = modelProject(project, [root]);
      expect(rows(verified['zones']).single['covered'], true);
      final withChild = modelProject(project, [
        root,
        {...working, 'id': 'segment', 'parentId': 'buyers'},
      ]);
      expect(rows(withChild['zones']).single['covered'], false);
      expect(
        rows(withChild['zones']).single['issues'],
        contains('Подальфы требуют внимания'),
      );
      expect(root['description'], '  Модель\nУточнение  ');
    },
  );

  test('a local queued alpha updates coverage without waiting for server snapshots', () {
    final folder = Directory.systemTemp.createTempSync('iw-modeler-');
    final db = LocalDatabase('${folder.path}/local.sqlite');
    final repo = DashboardRepository(db);
    db.set('serverId', 'owner');
    db.set('automaticSync', false);
    db.capture('portfolio', {
      'projects': [project],
      'alphas': [
        {...root, 'state': 'empty', 'filledDate': null},
      ],
    });
    repo.nativeSave('portfolio', 'updateAlpha', {
      ...root,
      'expectedRevision': 0,
    }, 'alpha:buyers');
    final view = modelProject(project, repo.entities('alphas', 'alpha'));
    expect(object(view['summary'])['filled'], 1);
    expect(rows(view['zones']).single['covered'], true);
    expect(repo.pending, hasLength(1));
    expect(rows(db.snapshot('portfolio')['alphas']).single['state'], 'empty');
    repo.dispose();
  });

  testWidgets(
    'projects start as a table; the selected project opens its own alpha and history',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('iw-modeler-ui-');
      final db = LocalDatabase('${folder.path}/local.sqlite');
      final repo = DashboardRepository(db);
      db.set('automaticSync', false);
      db.capture('portfolio', {
        'projects': [project],
        'alphas': [root],
      });
      Json? edited;
      String? zone;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ModelingWorkspace(
                repo: repo,
                createProject: () async {},
                editProject: (_) async {},
                editAlpha: (p, a) async {
                  edited = a;
                },
                createInZone: (p, z) async {
                  zone = z['id'].toString();
                },
                createChild: (p, a) async {},
                focusAlpha: (_) async {},
                linkSystem: (_) async {},
                characteristics: (_) => const SizedBox(),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Покупатели дома'), findsNothing);
      await tester.ensureVisible(find.text('Открыть моделер'));
      await tester.tap(find.text('Открыть моделер'));
      await tester.pump();
      expect(find.byType(DataTable), findsNWidgets(2));
      expect(db.get('modelerProjectId'), 'house');
      await tester.tap(find.byTooltip('Добавить альфу в зону'));
      expect(zone, 'customers');
      await tester.ensureVisible(find.text('Карточка альфы'));
      await tester.tap(find.text('Карточка альфы'));
      await tester.pump();
      await tester.ensureVisible(find.text('Записать').first);
      await tester.tap(find.text('Записать').first);
      expect(edited?['id'], 'buyers');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
}
