import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/pomodoro_plan.dart';
import 'package:indicators_work/repository.dart';

void main() {
  test(
    'daily rules apply indefinitely; edits and removal preserve earlier dates',
    () {
      final records = <Json>[
        {
          'date': '2026-10-15',
          'workRef': 'case:a',
          'title': '  Моя норма  ',
          'target': 10,
          'repeat': 'daily',
        },
        {
          'date': '2026-10-17',
          'workRef': 'case:a',
          'title': '  Моя норма  ',
          'target': 2,
          'repeat': 'daily',
        },
        {
          'date': '2026-10-19',
          'workRef': 'case:a',
          'title': '  Моя норма  ',
          'target': null,
          'repeat': 'daily',
        },
      ];
      expect(pomodoroTargetsOn(records, '2026-10-14'), isEmpty);
      expect(pomodoroTargetsOn(records, '2026-10-16').single['target'], 10);
      expect(pomodoroTargetsOn(records, '2026-10-18').single['target'], 2);
      expect(pomodoroTargetsOn(records, '2036-10-15'), isEmpty);
      expect(pomodoroWeekRows(records, [], '2026-10-12').single['target'], 24);
    },
  );
  test(
    'new offline norms recur and removing one does not return an earlier norm',
    () async {
      final db = LocalDatabase(':memory:')..set('serverId', 'owner');
      db.capture('dailyNorms', {
        'pomodoroTargets': [
          {
            'date': '2026-10-15',
            'workRef': 'case:a',
            'title': 'Точное имя',
            'target': 10,
            'repeat': 'daily',
          },
        ],
      });
      final repo = DashboardRepository(
        db,
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      repo.nativeSave('pomodoroTarget', 'save', {
        'date': '2026-10-17',
        'workRef': 'case:a',
        'title': 'Точное имя',
        'target': null,
      }, 'pomodoro:2026-10-17:case:a');
      expect(object(repo.pending.single['body'])['input']['repeat'], 'daily');
      expect(
        repo.pomodoroTargetsForDate('2026-10-16').single['actualPomodoros'],
        0,
      );
      expect(repo.pomodoroTargetsForDate('2036-10-15'), isEmpty);
      await Future<void>.delayed(Duration.zero);
      repo.dispose();
    },
  );
  test('cached recurring norm prevents tomorrow missing-plan question and does not copy facts', () {
    final db = LocalDatabase(':memory:')..set('serverId', 'owner');
    db.capture('dailyNorms', {
      'pomodoroTargets': [
        {
          'date': pomodoroShift(today(), -1),
          'workRef': 'case:a',
          'title': 'Точное имя',
          'target': 10,
          'repeat': 'daily',
        },
      ],
      'pomodoroFacts': [
        {
          'date': pomodoroShift(today(), -1),
          'workRef': 'case:a',
          'sessionId': 'yesterday',
          'count': 1,
        },
      ],
    });
    final repo = DashboardRepository(db);
    expect(repo.hasPomodoroPlan, true);
    expect(repo.pomodoroTargetsForDate().single['actualPomodoros'], 0);
    expect(
      repo.pomodoroTargetsForDate(pomodoroShift(today(), 1)).single['target'],
      10,
    );
    expect(
      repo.pomodoroTargetsForDate('2036-10-15').single['title'],
      'Точное имя',
    );
    repo.dispose();
  });
}
