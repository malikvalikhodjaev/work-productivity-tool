import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/focus_gallery_settings.dart';
import 'package:indicators_work/pomodoro_widgets.dart';

class CountingRepository extends DashboardRepository {
  int portfolioReads = 0;
  CountingRepository(super.local);
  @override
  Json cache(String key) {
    if (key == 'portfolio') portfolioReads++;
    return super.cache(key);
  }
}

void main() {
  testWidgets('seconds do not rebuild or reread project tables', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = LocalDatabase(':memory:');
    final repo = CountingRepository(db);
    await tester.pumpWidget(
      DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Проекты и модели').first,
    );
    await tester.pump();
    final reads = repo.portfolioReads;
    expect(reads, greaterThan(0));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(repo.portfolioReads, reads);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });

  testWidgets('timer settings are only built after opening settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = DashboardRepository(LocalDatabase(':memory:'));
    await tester.pumpWidget(
      DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Работа').first);
    await tester.pump();
    expect(find.byType(FocusGallerySettings), findsNothing);
    final settings = find.byKey(const ValueKey('timer-settings-button'));
    await tester.ensureVisible(settings);
    await tester.pumpAndSettle();
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(find.byType(FocusGallerySettings), findsOneWidget);
    expect(find.text('Тема и звук'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть настройки таймера'));
    await tester.pumpAndSettle();
    expect(find.byType(FocusGallerySettings), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    repo.dispose();
  });

  testWidgets(
    'neutral capacity uses configured duration and warning text only',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PomodoroCapacityNotice(
              workMinutes: 30,
              summary: {
                'actualPomodoros': 2,
                'limit': 8,
                'over': true,
                'message': 'Проверь план с учётом своих сил.',
              },
            ),
          ),
        ),
      );
      expect(find.text('До лимита: 6 (3 ч)'), findsOneWidget);
      final warning = tester.widget<Text>(
        find.text('Проверь план с учётом своих сил.'),
      );
      expect(warning.style!.color, const Color(0xffb3261e));
      final box = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(PomodoroCapacityProgress),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).color, const Color(0xfff3f4f4));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PomodoroCapacityNotice(
              summary: {
                'actualPomodoros': 2,
                'limit': 8,
                'over': false,
                'message': 'План: 6.',
              },
            ),
          ),
        ),
      );
      expect(find.text('До лимита: 6 (2,5 ч)'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.text('Всё в пределах лимита. План: 6.'))
            .style!
            .color,
        const Color(0xff347558),
      );
    },
  );
}
