import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/active_timer_conflict.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/focus_repository.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/section_analytics.dart';

LocalDatabase seed() => LocalDatabase(':memory:')
  ..set('serverId', 'owner')
  ..set('automaticSync', false)
  ..set('durableTimerEnabled', true)
  ..capture('timer', {
    'revision': 0,
    'settings': timerDefaults,
    'active': null,
    'sessions': [],
    'offlineCommands': true,
  });

class ClockFocusRepository extends FocusRepository {
  int clock;
  ClockFocusRepository(super.local, this.clock);
  @override
  int get now => clock;
}

void main() {
  test(
    'free play stores one durable command without a card, norm or network',
    () async {
      final repo = DashboardRepository(seed());
      addTearDown(repo.dispose);
      await Future.wait([
        repo.startUnplannedActivity(),
        repo.startUnplannedActivity(),
      ]);
      final session = repo.active!;
      expect(session['workRef'], isNull);
      expect(session['metricId'], isNull);
      expect(session['allocation'], 'outside');
      expect(session['workType'], isNull);
      expect(repo.pending.length, 1);
      final input = object(object(repo.pending.single['body'])['input']);
      expect(input['workRef'], isNull);
      expect(input['metricId'], isNull);
      expect(repo.pomodoroRows, isEmpty);
      await repo.timerAction('pause');
      expect(repo.active!['status'], 'paused');
      await repo.timerAction('resume');
      expect(repo.active!['id'], session['id']);
      expect(repo.pending.map((q) => object(q['body'])['action']), [
        'start',
        'pause',
        'resume',
      ]);
    },
  );
  test(
    'free play preserves another active work and its unsent commands',
    () async {
      final repo = DashboardRepository(seed());
      addTearDown(repo.dispose);
      await repo.focusWork(ref: 'work:a', title: 'Работа без норматива');
      final session = Map<String, dynamic>.from(repo.active!);
      final commands = repo.pending.length;
      await expectLater(
        repo.startUnplannedActivity(),
        throwsA(isA<ActiveTimerConflict>()),
      );
      expect(repo.active, session);
      expect(repo.pending.length, commands);
    },
  );
  test(
    'completed free pomodoro counts once in total and no planned work',
    () async {
      final day = today(), db = LocalDatabase(':memory:');
      final repo = ClockFocusRepository(
        db,
        DateTime.parse('${day}T10:00:00Z').millisecondsSinceEpoch,
      );
      addTearDown(repo.dispose);
      db.capture('dailyNorms', {
        'pomodoroTargets': [
          {
            'date': day,
            'repeat': 'daily',
            'workRef': 'work:planned',
            'title': 'Плановая работа',
            'target': 2,
          },
        ],
        'pomodoroCapacities': [
          {'date': day, 'limit': 8},
        ],
      });
      await repo.startUnplannedActivity();
      final id = repo.active!['id'];
      repo.clock += 1500000;
      await repo.timerAction('finish');
      expect(repo.pomodoroFacts.single['sessionId'], id);
      expect(repo.pomodoroFacts.single['workRef'], isNull);
      expect(repo.pomodoroCapacityForDate(day)['actualPomodoros'], 1);
      expect(repo.pomodoroTargetsForDate(day).single['actualPomodoros'], 0);
      expect(
        analyticsTimeRows(repo)
            .fold<num>(0, (sum, r) => sum + (r['durationSeconds'] as num)),
        1500,
      );
      expect(repo.pending, isEmpty);
    },
  );
  for (final mode in ['pomodoro', 'stopwatch']) {
    test(
      'short free $mode session records time without a full pomodoro',
      () async {
        final repo = ClockFocusRepository(
          LocalDatabase(':memory:'),
          DateTime.parse('${today()}T10:00:00Z').millisecondsSinceEpoch,
        );
        addTearDown(repo.dispose);
        repo.local.set('timerMode', mode);
        await repo.startUnplannedActivity();
        repo.clock += 120000;
        await repo.timerAction('finish');
        expect(repo.pomodoroFacts, isEmpty);
        expect(
          analyticsTimeRows(repo)
              .fold<num>(0, (sum, r) => sum + (r['durationSeconds'] as num)),
          120,
        );
      },
    );
  }
  for (final mobile in [false, true]) {
    testWidgets(
      'visible free play and pause work without a form on ${mobile ? 'Android' : 'desktop'}',
      (tester) async {
        tester.view.physicalSize = Size(mobile ? 390 : 1400, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = DashboardRepository(seed());
        await tester.pumpWidget(
          DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
        );
        if (mobile) {
          await tester.tap(find.text('Работа').first);
        } else {
          await tester.tap(find.widgetWithText(FilledButton, 'Работа').first);
        }
        await tester.pump(const Duration(milliseconds: 400));
        final play = find.byKey(const ValueKey('start-unplanned-timer')).first;
        await tester.ensureVisible(play);
        await tester.pumpAndSettle();
        await tester.tap(play);
        await tester.pump(const Duration(milliseconds: 400));
        final id = repo.active!['id'];
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Начать фокус'), findsNothing);
        expect(repo.active!['workRef'], isNull);
        final pause = find.widgetWithText(FilledButton, 'Пауза').first;
        await tester.ensureVisible(pause);
        await tester.pumpAndSettle();
        await tester.tap(pause);
        await tester.pump(const Duration(milliseconds: 400));
        expect(repo.active!['status'], 'paused');
        final resume = find.widgetWithText(FilledButton, 'Продолжить').first;
        await tester.ensureVisible(resume);
        await tester.pumpAndSettle();
        await tester.tap(resume);
        await tester.pump(const Duration(milliseconds: 400));
        expect(repo.active!['id'], id);
        expect(repo.active!['status'], 'running');
        expect(repo.pomodoroRows, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        repo.dispose();
      },
      variant: TargetPlatformVariant.only(
        mobile ? TargetPlatform.android : TargetPlatform.windows,
      ),
    );
  }
}
