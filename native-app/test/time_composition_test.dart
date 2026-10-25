import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/time_composition.dart';

void main() {
  test(
    'hours, pomodoros and percentages have separate measured denominators',
    () {
      final result = timeComposition(
        [
          {'durationSeconds': 3600, 'workType': 'investment'},
          {'amount': 2, 'workType': 'productive'},
          {'durationSeconds': 1800, 'workType': 'leasure'},
          {'durationSeconds': 1800, 'workType': 'Диагностика'},
        ],
        [
          {'sessionId': 'a'},
          {'sessionId': 'a'},
          {'sessionId': 'b'},
          {'sessionId': 'missing'},
        ],
        {
          'a': {'workType': 'investment'},
          'b': {'workType': 'productive'},
        },
      );
      final by = {for (final r in result) r['type']: r};
      expect(by['investment']!['seconds'], 3600);
      expect(by['investment']!['percent'], 25);
      expect(by['productive']!['percent'], 50);
      expect(by['leisure']!['percent'], 12.5);
      expect(by['waste']!['seconds'], 0);
      expect(by['unclassified']!['seconds'], 1800);
      expect(result.fold<int>(0, (n, r) => n + (r['pomodoros'] as int)), 3);
      expect(by['investment']!['pomodoroPercent'], closeTo(100 / 3, .0001));
      expect(by['unclassified']!['pomodoros'], 1);
    },
  );
  test('empty or invalid time never invents waste or a percentage', () {
    final result = timeComposition(
      [
        {'durationSeconds': -5},
        {'durationSeconds': double.nan},
      ],
      [],
      {},
    );
    expect(
      result.every(
        (r) =>
            r['percent'] == null &&
            r['pomodoroPercent'] == null &&
            r['seconds'] == 0,
      ),
      true,
    );
    expect(timeTypeOptions('Диагностика').containsKey('Диагностика'), true);
  });
  test('explicit pauses and leisure remain disjoint across local midnight and duplicate snapshots', () {
    final db = LocalDatabase(':memory:');
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    int at(String time) =>
        DateTime.parse('2026-10-24T$time:00Z').millisecondsSinceEpoch;
    var s = newLocalSession(title: 'Test', mode: 'stopwatch', now: at('18:58'));
    s = changeLocalSession(s, 'pause', at('18:59'));
    expect(currentPauseMs(s, at('19:00')), 60000);
    expect(elapsedMs(s, at('19:00')), 60000);
    s = changeLocalSession(
      s,
      'leisure',
      at('19:01'),
      leisureUntil: at('19:04'),
    );
    s = changeLocalSession(s, 'resume', at('19:04'));
    s = changeLocalSession(s, 'pause', at('19:05'));
    s = changeLocalSession(s, 'resume', at('19:06'));
    s = changeLocalSession(s, 'finish', at('19:08'));
    db.capture('timer', {
      'sessions': [s],
    });
    db.set('sharedLocalHistory', [s]);
    final rest = analyticsRestRows(repo);
    double total(String kind) => rest
        .where((r) => r['workType'] == kind)
        .fold<double>(0, (n, r) => n + r['durationSeconds']);
    expect(total('leisure'), 180);
    expect(total('unclassified'), 180);
    expect(
      rest
          .where((r) => r['date'] == '2026-10-24')
          .fold<double>(0, (n, r) => n + r['durationSeconds']),
      60,
    );
    expect(elapsedMs(s, at('19:08')), 240000);
    expect(s['completedPomodoros'], 0);
  });
}
