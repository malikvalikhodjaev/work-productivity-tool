import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/goal_hierarchy.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/model_hierarchy.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/sync_conflicts.dart';

List<Json> initial() => [
  {
    'id': 'a',
    'title': 'Основная',
    'parentId': null,
    'sortOrder': 0,
    'status': 'active',
  },
  {
    'id': 'b',
    'title': 'Другая',
    'parentId': null,
    'sortOrder': 1,
    'status': 'active',
  },
  {
    'id': 'c',
    'title': 'Дочерняя',
    'parentId': 'a',
    'sortOrder': 0,
    'status': 'active',
  },
];
Json workspace(List<Json> goals) => {
  'goals': goals,
  'goalGridVersion': 1,
  'goalHierarchyVersion': 1,
  'goalFieldEditingVersion': 1,
};
Json timer() => {
  'revision': 0,
  'active': null,
  'sessions': [],
  'settings': timerDefaults,
  'offlineCommands': true,
};
void seed(LocalDatabase db) {
  db.set('serverId', 'owner');
  db.set('automaticSync', false);
  db.set(
    'reminderSnoozeUntil',
    DateTime.now().millisecondsSinceEpoch + 3600000,
  );
  db.capture('workspace', workspace(initial()));
  db.capture('timer', timer());
}

http.Response reply(Json value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('later creations never acquire sortOrder from earlier pending moves; persisted queue sends without self-conflicts', () async {
    final folder = Directory.systemTemp.createTempSync('iw-goal-order-');
    addTearDown(() {
      expect(
        folder.absolute.path.startsWith(
          '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}',
        ),
        true,
      );
      folder.deleteSync(recursive: true);
    });
    final file = '${folder.path}/device.sqlite';
    var serverRows = initial(), golden = initial();
    final receipts = <String, String>{},
        accepted = <String>[],
        sent = <String>[];
    var loseCreationResponse = true;
    http.Client client() => MockClient((request) async {
      if (request.url.path == '/api/offline/connect')
        return reply({'serverId': 'owner', 'offlineCommands': true});
      if (request.method == 'GET')
        return reply(
          request.url.path == '/api/workspace'
              ? workspace(serverRows)
              : request.url.path == '/api/timer'
              ? timer()
              : {},
        );
      final body = object(jsonDecode(request.body)),
          input = object(body['input']),
          id = body['requestId'].toString();
      sent.add(id);
      if (receipts.containsKey(id)) {
        expect(receipts[id], request.body);
        return reply({'workspace': workspace(serverRows)});
      }
      if (body['action'] == 'moveGoal') {
        if (input['expectedHierarchy'] != goalHierarchySignature(serverRows))
          return reply({
            'error': 'Иерархия индикаторов уже изменилась. Перемещение сохранено для разбора.',
          }, 409);
        serverRows = relocateGoal(serverRows, input);
      } else if (body['action'] == 'saveGoal') {
        // Server creation does not assign an order until a later move.
        serverRows = [
          ...serverRows,
          {
            ...input,
            'id': input['clientId'],
            'parentId': parentOf(input),
            'sortOrder': null,
          },
        ];
      } else {
        throw StateError('Unexpected command');
      }
      accepted.add(id);
      receipts[id] = request.body;
      if (body['action'] == 'saveGoal' && loseCreationResponse) {
        loseCreationResponse = false;
        throw http.ClientException('Lost response after committed creation');
      }
      return reply({'workspace': workspace(serverRows)});
    });
    var db = LocalDatabase(file);
    seed(db);
    var repo = DashboardRepository(db, client: client());
    void check() => expect(
      goalHierarchySignature(repo.entities('goals', 'goal')),
      goalHierarchySignature(golden),
    );
    void move(String id, String? parent, {String? before}) {
      final old = goalHierarchySignature(golden);
      repo.moveGoal({'id': id, 'parentId': parent, 'beforeId': before});
      final input = object(object(repo.pending.last['body'])['input']);
      expect(input['expectedHierarchy'], old);
      golden = relocateGoal(golden, input);
      check();
    }

    void create(String id) {
      final input = <String, dynamic>{
        'clientId': id,
        'title': '  Новая $id\nстрока  ',
        'parentId': '',
        'unit': 'шт',
        'direction': 'up',
        'status': 'active',
      };
      repo.nativeSave('workspace', 'saveGoal', input, 'goal:$id');
      golden = [
        ...golden,
        {...input, 'id': id, 'parentId': null, 'sortOrder': null},
      ];
      expect(
        repo
            .entities('goals', 'goal')
            .firstWhere((r) => r['id'] == id)['sortOrder'],
        isNull,
      );
      check();
    }

    move('b', 'a');
    move('c', null);
    final early = repo.pending.map((q) => jsonEncode(q['body'])).toList();
    create('first');
    move('a', 'first');
    move('b', 'first', before: 'a');
    create('second');
    move('first', 'second');
    create('third');
    move('third', 'second', before: 'first');
    move('a', 'third');
    expect(
      repo.pending.take(early.length).map((q) => jsonEncode(q['body'])),
      early,
    );
    final original = repo.pending.map((q) => jsonEncode(q['body'])).toList();
    await repo.synchronize();
    expect(repo.pending, isNotEmpty);
    expect(repo.pending.any((q) => q['state'] == 'conflict'), false);
    // Restart with the failed HTTP response and remaining commands intact.
    repo.dispose();
    db = LocalDatabase(file);
    repo = DashboardRepository(db, client: client());
    await repo.synchronize();
    expect(repo.pending, isEmpty);
    expect(repo.local.get('lastSyncError'), isNull);
    expect(accepted.length, original.length);
    expect(accepted.toSet().length, original.length);
    expect(sent.length, greaterThan(accepted.length));
    expect(goalHierarchySignature(serverRows), goalHierarchySignature(golden));
    expect(
      goalHierarchySignature(repo.entities('goals', 'goal')),
      goalHierarchySignature(golden),
    );
    expect(
      serverRows.firstWhere((r) => r['id'] == 'third')['title'],
      '  Новая third\nстрока  ',
    );
    repo.dispose();
  });

  test('only a stale goal hierarchy gets the non-retry explanation', () {
    final item = <String, dynamic>{
      'state': 'conflict',
      'body': {'module': 'workspace', 'action': 'moveGoal'},
      'error': 'Иерархия индикаторов уже изменилась. Перемещение сохранено для разбора.',
    };
    expect(isGoalHierarchyConflict(item), true);
    expect(isGoalHierarchyConflict({...item, 'error': 'Нет связи'}), false);
    expect(
      isGoalHierarchyConflict({
        ...item,
        'body': {'module': 'workspace', 'action': 'measure'},
      }),
      false,
    );
    expect(isGoalHierarchyConflict({...item, 'state': 'queued'}), false);
  });

  testWidgets(
    'stale move offers current-structure choice instead of an ineffective retry',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = LocalDatabase(':memory:');
      seed(db);
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      repo.moveGoal({'id': 'b', 'parentId': 'a', 'beforeId': null});
      final command = repo.pending.single, raw = jsonEncode(command['body']);
      db.conflict(
        command['id'].toString(),
        'Иерархия индикаторов уже изменилась. Перемещение сохранено для разбора.',
      );
      await tester.pumpWidget(
        DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Данные').first);
      await tester.pumpAndSettle();
      final row = find.text(command['entity'].toString());
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text(goalHierarchyConflictHelp), findsOneWidget);
      expect(find.text('Повторить исходную команду'), findsNothing);
      expect(
        find.text('Применить перенос к текущей структуре'),
        findsOneWidget,
      );
      expect(find.text('Оставить серверный вариант'), findsOneWidget);
      expect(jsonEncode(repo.pending.single['body']), raw);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
