import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/repository.dart';

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'Android scrolls full checklist without shrinking content at $scale',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = LocalDatabase(':memory:');
        final repo = DashboardRepository(db);
        db.set(
          'pomodoroReminder:${today()}',
          DateTime.now().millisecondsSinceEpoch + 3600000,
        );
        db.capture('dailyNorms', {
          'pomodoroTargets': [
            for (var i = 0; i < 8; i++)
              {
                'date': today(),
                'repeat': 'daily',
                'workRef': 'work:$i',
                'title': 'Длинное читаемое название норматива $i',
                'target': 10,
              },
          ],
        });
        await tester.pumpWidget(
          DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
        );
        final home = find.byType(DashboardHome);
        final context = tester.element(home);
        final state = tester.state(home) as dynamic;
        state.setState(() {
          state.section = 2;
          state.focusMode = true;
        });
        await tester.pump();
        expect(Theme.of(context).platform, TargetPlatform.android);
        final scroll = find.byKey(const PageStorageKey('mobile-focus-scroll'));
        expect(scroll, findsOneWidget);
        final clock = find.text('25:00');
        expect(
          find.ancestor(of: clock, matching: find.byType(FittedBox)),
          findsNothing,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('pomodoro-title:work:7')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Длинное читаемое название норматива 7').hitTestable(),
          findsOneWidget,
        );
        final text = tester.widget<Text>(
          find.byKey(const ValueKey('pomodoro-title:work:7')),
        );
        expect(text.maxLines, null);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
