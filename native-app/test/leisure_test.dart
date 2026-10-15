import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/leisure.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/main.dart';

void main() {
  testWidgets('an old Leisure can be rescheduled after several days', (
    tester,
  ) async {
    final db = LocalDatabase(':memory:')..set('serverId', 'owner');
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = changeLocalSession(
      newLocalSession(title: 'Долгий отдых', now: now - 3 * 86400000),
      'leisure',
      now - 3 * 86400000 + 60000,
      leisureUntil: now - 3 * 86400000 + 900000,
    );
    db.set('localActive', session);
    final repo = DashboardRepository(db);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => chooseLeisure(context, repo),
              child: const Text('Изменить Leisure'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Изменить Leisure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Начать отдых'));
    await tester.pumpAndSettle();
    expect(object(repo.active?['leisure'])['until'], greaterThan(now));
    expect(
      object(repo.active?['leisure'])['start'],
      object(session['leisure'])['start'],
    );
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
  });
  test(
    'Leisure survives reconstruction and never adds work without manual return',
    () {
      const start = 1800000000000;
      var s = newLocalSession(title: 'Работа', now: start);
      s = changeLocalSession(
        s,
        'leisure',
        start + 600000,
        leisureUntil: start + 1500000,
      );
      s = object(jsonDecode(jsonEncode(s)));
      expect(s['status'], 'paused');
      expect(leisureDue(s, start + 1800000), true);
      expect(clockOf(s, start + 1800000), '00:00');
      expect(clockOf(s, start + 1800000, workOnly: true), '15:00');
      expect(elapsedMs(s, start + 1800000), 600000);
      s = changeLocalSession(s, 'resume', start + 1800000);
      expect(s['leisure'], isNull);
      expect(leisureElapsedMs(s, start + 1800000), 1200000);
      s = changeLocalSession(s, 'finish', start + 2700000);
      expect(elapsedMs(s, start + 2700000), 1500000);
      expect(s['completedPomodoros'], 1);
      expect(rows(s['leisureIntervals']), hasLength(1));
    },
  );
  test('invalid deadline preserves source; adjusting deadline does not reset rest start', () {
    const start = 1800000000000;
    var s = newLocalSession(title: 'Работа', now: start);
    final raw = jsonEncode(s);
    expect(
      () =>
          changeLocalSession(s, 'leisure', start + 60000, leisureUntil: start),
      throwsArgumentError,
    );
    expect(jsonEncode(s), raw);
    s = changeLocalSession(
      s,
      'leisure',
      start + 60000,
      leisureUntil: start + 300000,
    );
    s = changeLocalSession(
      s,
      'leisure',
      start + 120000,
      leisureUntil: start + 600000,
    );
    expect(object(s['leisure'])['start'], start + 60000);
  });
  testWidgets(
    'Leisure date/time form pauses work; Later keeps it paused and return resumes same session',
    (tester) async {
      final db = LocalDatabase(':memory:')..set('serverId', 'owner');
      final now = DateTime.now().millisecondsSinceEpoch;
      final s = newLocalSession(title: 'Моя работа', now: now - 60000);
      db.set('localActive', s);
      final repo = DashboardRepository(db);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => chooseLeisure(context, repo),
                    child: const Text('Leisure'),
                  ),
                  TextButton(
                    onPressed: () => askLeisureReturn(context, repo),
                    child: const Text('Открыть предложение'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Leisure'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Начать отдых'));
      await tester.pumpAndSettle();
      expect(repo.active?['status'], 'paused');
      expect(inLeisure(repo.active), true);
      expect(repo.active?['id'], s['id']);
      await tester.tap(find.text('Открыть предложение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Позже'));
      await tester.pumpAndSettle();
      expect(repo.active?['status'], 'paused');
      await tester.tap(find.text('Открыть предложение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Вернуться к работе'));
      await tester.pumpAndSettle();
      expect(repo.active?['status'], 'running');
      expect(repo.active?['id'], s['id']);
      expect(inLeisure(repo.active), false);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
  testWidgets(
    'elapsed leisure offers return once and Later never starts working',
    (tester) async {
      final db = LocalDatabase(':memory:')..set('serverId', 'owner');
      final now = DateTime.now().millisecondsSinceEpoch;
      var s = newLocalSession(title: 'Отдохнуть и вернуться', now: now - 60000);
      s = changeLocalSession(
        s,
        'leisure',
        now - 10000,
        leisureUntil: now - 1000,
      );
      db.set('localActive', s);
      final repo = DashboardRepository(db);
      await tester.pumpWidget(
        DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Вернуться к работе?'), findsOneWidget);
      expect(repo.active?['status'], 'paused');
      await tester.tap(find.text('Позже'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.active?['status'], 'paused');
      expect(repo.active?['id'], s['id']);
      expect(repo.pending, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
}
