import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/goal_progress.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';

void main() {
  test('manual before/after separates change from progress, including decreasing goals', () {
    final increasing = evaluateGoal(
      {'baseline': 10, 'target': 30, 'direction': 'up'},
      [
        {'value': 20},
        {'value': 16},
      ],
    );
    expect(increasing['delta'], 10);
    expect(increasing['lastChange'], 4);
    expect(increasing['percent'], 50);
    final decreasing = evaluateGoal(
      {'baseline': 20, 'target': 5, 'direction': 'down'},
      [
        {'value': 10},
      ],
    );
    expect(decreasing['delta'], -10);
    expect(decreasing['percent'], 67);
    expect(decreasing['reached'], false);
    final noTarget = evaluateGoal(
      {'baseline': 10},
      [
        {'value': 15},
      ],
    );
    expect(noTarget['delta'], 5);
    expect(noTarget['percent'], null);
    expect(evaluateGoal({'baseline': 0, 'target': 10}, [])['current'], null);
    expect(
      evaluateGoal(
        {'baseline': 5, 'target': 5},
        [
          {'value': 5},
        ],
      )['percent'],
      null,
    );
  });
  test('offline measurements update immediately, preserve raw evidence and keep historical date order', () {
    final db = LocalDatabase(':memory:');
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    db.set('serverId', 'own-archive');
    db.set('automaticSync', false);
    db.capture('workspace', {
      'goals': [
        {
          'id': 'g',
          'title': 'Test',
          'baseline': 0,
          'target': 20,
          'direction': 'up',
          'unit': 'units',
          'parentId': null,
        },
      ],
      'measurements': [
        {
          'id': 'old',
          'kind': 'goal',
          'targetId': 'g',
          'value': 4,
          'date': '2026-10-24',
          'createdAt': '2026-10-24T10:00:00Z',
        },
      ],
    });
    repo.nativeSave('workspace', 'measure', {
      'kind': 'goal',
      'targetId': 'g',
      'value': 10,
      'date': '2026-10-25',
      'evidence': '  raw\n evidence  ',
    }, 'measurement:new');
    repo.nativeSave('workspace', 'measure', {
      'kind': 'goal',
      'targetId': 'g',
      'value': 2,
      'date': '2026-10-23',
      'evidence': 'earlier',
    }, 'measurement:earlier');
    final before = jsonEncode(db.queue),
        original = jsonEncode(db.snapshot('workspace'));
    final goal = projectedGoals(repo).single;
    expect(goal['current'], 10);
    expect(goal['percent'], 50);
    expect(goal['delta'], 10);
    expect(goal['lastChange'], 6);
    expect(object(goal['measurement'])['pending'], true);
    expect(rows(goal['history']).first['evidence'], '  raw\n evidence  ');
    expect(jsonEncode(db.queue), before);
    expect(jsonEncode(db.snapshot('workspace')), original);
    db.conflict(db.queue.first['id'], 'test conflict');
    expect(projectedGoals(repo).single['current'], 4);
  });
  test('linked characteristic is one source and child progress does not invent parent progress', () {
    final db = LocalDatabase(':memory:');
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    db.capture('workspace', {
      'goals': [
        {'id': 'parent', 'baseline': 0, 'target': 100},
        {
          'id': 'child',
          'parentId': 'parent',
          'characteristicId': 'c',
          'baseline': 0,
          'target': 10,
        },
      ],
      'measurements': [
        {
          'kind': 'characteristic',
          'targetId': 'c',
          'date': '2026-10-25',
          'value': 8,
        },
      ],
    });
    final goals = projectedGoals(repo);
    expect(goals.first['percent'], null);
    expect(goals.last['current'], 8);
    expect(goals.last['percent'], 80);
  });
}
