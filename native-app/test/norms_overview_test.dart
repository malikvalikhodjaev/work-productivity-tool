import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/activity_status.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/norms_overview.dart';
import 'package:indicators_work/repository.dart';

void main() {
  test('weekly norms use only effective owner rules, retain changes by day and never template targets', () {
    final db = LocalDatabase(':memory:')
      ..set('automaticSync', false)
      ..capture('dashboard', {
        'metrics': [
          {'id': 'guides', 'title': 'Шаблон', 'target': 10},
        ],
      })
      ..capture('dailyNorms', {
        'pomodoroTargets': [
          {
            'workRef': 'work:w',
            'title': 'Мой футбол',
            'date': '2026-10-26',
            'target': 10,
            'repeat': 'daily',
          },
          {
            'workRef': 'work:w',
            'title': 'Мой футбол',
            'date': '2026-10-28',
            'target': 5,
            'repeat': 'daily',
          },
          {
            'workRef': 'work:w',
            'title': 'Мой футбол',
            'date': '2026-10-30',
            'target': null,
            'repeat': 'daily',
          },
        ],
        'pomodoroFacts': [
          {
            'sessionId': 's',
            'workRef': 'work:w',
            'date': '2026-10-27',
            'count': 1,
          },
        ],
      })
      ..capture('entries', {
        'entries': [
          {
            'workRef': 'work:w',
            'date': '2026-10-27',
            'durationSeconds': 1500,
            'timerSessionId': 's',
          },
        ],
      });
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    final raw = db.snapshot('dailyNorms').toString();
    final rows = userNormsWeek(repo, '2026-10-26');
    expect(rows, hasLength(1));
    expect(rows.single['title'], 'Мой футбол');
    expect(rows.single['planned'], 30);
    expect(rows.single['actual'], 1);
    expect(rows.single['hours'], closeTo(1500 / 3600, .000001));
    expect(userNormsWeek(repo, '2026-10-19'), isEmpty);
    expect(db.snapshot('dailyNorms').toString(), raw);
    expect(repo.pending, isEmpty);
  });
  testWidgets(
    'empty owner norms never display coded template names or targets',
    (tester) async {
      final db = LocalDatabase(':memory:')
        ..set('automaticSync', false)
        ..capture('dashboard', {
          'metrics': [
            {'title': 'Шаблон из кода', 'target': 10},
          ],
        });
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NormsOverview(repo: repo)),
        ),
      );
      expect(find.text('Шаблон из кода'), findsNothing);
      expect(find.textContaining('своих нормативов нет'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'compact synchronization fits in the header and keeps the complete status accessible',
    (tester) async {
      final db = LocalDatabase(':memory:')
        ..set('lastSyncAt', '2026-10-26T18:45:00Z');
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ActivityStatus(repo: repo, compact: true, showTimer: false),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('activity-status')), findsNothing);
      expect(
        find.byKey(const ValueKey('activity-status-compact')),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Синхронизировано · 23:45\nСинхронизировать сейчас'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
