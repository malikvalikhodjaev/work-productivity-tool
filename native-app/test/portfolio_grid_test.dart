import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/grid_definitions.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/portfolio_grid.dart';
import 'package:indicators_work/repository.dart';

void main() {
  test('Explicit conflict resolution retains the original and rebases only changed cells with a fresh UUID', () async {
    final folder = Directory.systemTemp.createTempSync('iw-grid-conflict-');
    final db = LocalDatabase('${folder.path}/local.sqlite');
    db.set('serverId', 'owner');
    db.set('automaticSync', false);
    final fresh = <String, dynamic>{
      'tableEditing': 1,
      'tableDefinitions': defaultGridColumns,
      'projects': [
        {'id': 'house', 'name': 'Изменено на сервере'},
      ],
    };
    db.capture('portfolio', fresh);
    final repo = DashboardRepository(
      db,
      client: MockClient(
        (request) async =>
            http.Response.bytes(utf8.encode(jsonEncode(fresh)), 200),
      ),
    );
    repo.gridCommand('editCells', {
      'table': 'projects',
      'id': 'house',
      'changes': [
        {'columnId': 'name', 'before': 'Прежнее имя', 'value': 'Моя правка'},
      ],
    });
    final original = repo.pending.single;
    db.conflict(original['id'] as String, 'Конфликт ячейки');
    await repo.resolveConflict(repo.pending.single, apply: true);
    final replacement = object(repo.pending.single['body']);
    expect(
      replacement['requestId'],
      isNot(object(original['body'])['requestId']),
    );
    expect(rows(object(replacement['input'])['changes']).single, {
      'columnId': 'name',
      'before': 'Изменено на сервере',
      'value': 'Моя правка',
    });
    expect(rows(db.get('conflictHistory')).single['body'], original['body']);
    repo.dispose();
  });
  final project = <String, dynamic>{
    'id': 'house',
    'name': 'Продажа дома',
    'status': 'active',
    'phase': 'pre_operation',
    'zones': [],
  };
  DashboardRepository open(String file, {bool seed = false}) {
    final db = LocalDatabase(file);
    if (seed) {
      db.set('serverId', 'owner');
      db.set('automaticSync', false);
      db.capture('portfolio', {
        'tableEditing': 1,
        'tableDefinitions': defaultGridColumns,
        'projects': [project],
        'alphas': [],
      });
    }
    return DashboardRepository(db);
  }

  test('Several cells and a new typed column survive offline restart without clobbering snapshots or commands', () {
    final folder = Directory.systemTemp.createTempSync('iw-grid-local-'),
        file = '${folder.path}/local.sqlite';
    var repo = open(file, seed: true);
    final id = uuid.v4();
    repo.gridCommand('createColumn', {
      'table': 'projects',
      'id': id,
      'title': 'Риелтор',
      'type': 'text',
    });
    repo.gridCommand('editCells', {
      'table': 'projects',
      'id': 'house',
      'changes': [
        {'columnId': id, 'before': null, 'value': '  Контакт\nПозвонить  '},
      ],
    });
    repo.gridCommand('editCells', {
      'table': 'projects',
      'id': 'house',
      'changes': [
        {'columnId': 'name', 'before': 'Продажа дома', 'value': 'Дом'},
      ],
    });
    final first = repo.pending.map((q) => q['body']).toList();
    repo.local.attempted(repo.pending.first['id'] as String);
    repo.gridCommand('editCells', {
      'table': 'projects',
      'id': 'house',
      'changes': [
        {
          'columnId': id,
          'before': '  Контакт\nПозвонить  ',
          'value': 'Обновлённый контакт',
        },
      ],
    });
    expect(repo.pending.take(3).map((q) => q['body']).toList(), first);
    expect(
      rows(repo.cache('portfolio')['projects']).single['name'],
      'Продажа дома',
    );
    repo.dispose();
    repo = open(file);
    final row = repo.entities('projects', 'project').single;
    expect(row['name'], 'Дом');
    expect(object(row['customValues'])[id], 'Обновлённый контакт');
    expect(repo.gridColumns('projects').last['title'], 'Риелтор');
    expect(repo.pending, hasLength(4));
    repo.dispose();
  });
  testWidgets(
    'A cell editor keeps typed paragraphs and focus while repository updates; save queues locally',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('iw-grid-editor-');
      final repo = open('${folder.path}/local.sqlite', seed: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: repo,
                builder: (context, _) => PortfolioGrid(
                  repo: repo,
                  table: 'projects',
                  items: repo.entities('projects', 'project'),
                  addRow: () async {},
                  openRow: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Продажа дома'));
      await tester.pumpAndSettle();
      final cell = find.byKey(const ValueKey('inline:projects:house:name'));
      final input = find.descendant(of: cell, matching: find.byType(TextField));
      await tester.enterText(input, '  Дом\nМой план  ');
      final editable = tester.widget<EditableText>(
        find.descendant(of: cell, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      for (var i = 0; i < 4; i++) {
        repo.notifyListeners();
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        tester.widget<TextField>(input).controller!.text,
        '  Дом\nМой план  ',
      );
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(
        repo.entities('projects', 'project').single['name'],
        '  Дом\nМой план  ',
      );
      expect(repo.pending, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.dispose();
    },
  );
}
