import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/goal_hierarchy.dart';
import 'package:indicators_work/model_hierarchy.dart';
import 'package:indicators_work/goal_table.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/local_database.dart';

List<Json> sample() => [
  {
    'id': 'a',
    'title': '  Исходный\nтекст  ',
    'sortOrder': 0,
    'status': 'active',
    'physicalSystem': '  Дом  ',
    'customValues': {'note': '\nraw '},
    'updatedAt': 'old',
  },
  {
    'id': 'b',
    'parentId': 'a',
    'sortOrder': 0,
    'title': 'Дочерняя',
    'status': 'active',
  },
  {
    'id': 'c',
    'parentId': 'b',
    'sortOrder': 0,
    'title': 'Глубже',
    'status': 'active',
  },
  {'id': 'd', 'sortOrder': 1, 'title': 'Другая', 'status': 'active'},
  {'id': 'e', 'sortOrder': 2, 'title': 'Архив', 'status': 'archived'},
];
DashboardRepository repository() => DashboardRepository(
  LocalDatabase(':memory:')
    ..set('serverId', 'test')
    ..set('automaticSync', false)
    ..capture('workspace', {
      'goals': sample(),
      'goalHierarchyVersion': 1,
      'goalGridVersion': 1,
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
  test('canonical signature matches server and a branch moves intact between any levels', () {
    final source = sample(), raw = jsonEncode(source);
    expect(
      goalHierarchySignature(source),
      '[["a",null,0,false,null],["b","a",0,false,null],["c","b",0,false,null],["d",null,1,false,null],["e",null,2,true,null]]',
    );
    var next = relocateGoal(
      source,
      goalDropInput(source, 'd', source[0], 'before'),
    );
    expect(orderedSiblings(next).map((g) => g['id']), ['d', 'a', 'e']);
    next = relocateGoal(next, goalDropInput(next, 'a', source[3], 'inside'));
    expect(next.firstWhere((r) => r['id'] == 'a')['parentId'], 'd');
    expect(next.firstWhere((r) => r['id'] == 'c')['parentId'], 'b');
    next = relocateGoal(next, goalDropInput(next, 'b', null, 'root'));
    expect(parentOf(next.firstWhere((r) => r['id'] == 'b')), null);
    expect(next.first['title'], source.first['title']);
    expect(jsonEncode(source), raw);
    for (final input in [
      {'id': 'a', 'parentId': 'c'},
      {'id': 'a', 'parentId': 'e'},
      {'id': 'a', 'beforeId': 'b'},
    ]) {
      expect(() => relocateGoal(source, input), throwsStateError);
    }
  });
  test('queued moves project in order, survive a fresh snapshot and never hide custom values or stale row drafts', () {
    final repo = repository();
    addTearDown(repo.dispose);
    repo.editGoalField('b', 'title', '  Сохранённый\nтекст  ');
    repo.moveGoal({'id': 'b', 'parentId': 'd', 'beforeId': null});
    repo.editGoalField('b', 'unit', 'ч');
    expect(
      repo
          .entities('goals', 'goal')
          .firstWhere((g) => g['id'] == 'b')['parentId'],
      'd',
      reason: jsonEncode(repo.pending),
    );
    final command = repo.pending.firstWhere(
      (q) => object(q['body'])['action'] == 'moveGoal',
    );
    final payload = jsonEncode(command['body']);
    repo.local.capture('workspace', {
      'goals': sample(),
      'goalHierarchyVersion': 1,
      'goalGridVersion': 1,
    });
    expect(
      repo
          .entities('goals', 'goal')
          .firstWhere((g) => g['id'] == 'b')['parentId'],
      'd',
    );
    expect(jsonEncode(command['body']), payload);
    repo.local.capture('workspace', {
      'goals': relocateGoal(sample(), object(object(command['body'])['input'])),
      'goalHierarchyVersion': 1,
      'goalGridVersion': 1,
    });
    repo.local.acknowledge(command['id'].toString());
    final row = repo
        .entities('goals', 'goal')
        .firstWhere((g) => g['id'] == 'b');
    expect(row['parentId'], 'd');
    expect(row['title'], '  Сохранённый\nтекст  ');
    expect(
      repo.entities('goals', 'goal').first['customValues'],
      sample().first['customValues'],
    );
  });
  for (final mobile in [false, true]) {
    testWidgets(
      'drag nests a branch and promotes it to root (${mobile ? 'touch' : 'mouse'})',
      (tester) async {
        debugDefaultTargetPlatformOverride = mobile
            ? TargetPlatform.android
            : TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final repo = repository();
        addTearDown(repo.dispose);
        tester.view.physicalSize = const Size(1500, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(page(repo));
        await tester.pumpAndSettle();
        Future<void> start(String id) async {
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(ValueKey('goal-drag:$id'))),
          );
          if (mobile) await tester.pump(const Duration(milliseconds: 600));
          await gesture.moveBy(const Offset(24, 0));
          await tester.pump();
          final target = tester.getRect(
            find.byKey(const ValueKey('goal-drop:d')),
          );
          await gesture.moveTo(Offset(target.left + 180, target.center.dy));
          await tester.pump();
          expect(
            find.byKey(const ValueKey('goal-drop-guide:inside')),
            findsOneWidget,
          );
          await gesture.up();
          await tester.pumpAndSettle();
        }

        await start('a');
        expect(
          repo
              .entities('goals', 'goal')
              .firstWhere((g) => g['id'] == 'a')['parentId'],
          'd',
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('goal-drag:a'))),
        );
        if (mobile) await tester.pump(const Duration(milliseconds: 600));
        await gesture.moveBy(const Offset(24, 0));
        await tester.pump();
        await gesture.moveTo(
          tester.getCenter(find.byKey(const ValueKey('goal-drop-root'))),
        );
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(
          parentOf(
            repo.entities('goals', 'goal').firstWhere((g) => g['id'] == 'a'),
          ),
          null,
        );
        expect(
          repo
              .entities('goals', 'goal')
              .firstWhere((g) => g['id'] == 'c')['parentId'],
          'b',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
