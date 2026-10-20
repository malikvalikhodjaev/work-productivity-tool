import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/focus_main.dart';
import 'package:indicators_work/focus_repository.dart';
import 'package:indicators_work/local_database.dart';

void main() {
  testWidgets(
    'first standalone norm creates work without login and Play starts it',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FocusRepository(LocalDatabase(':memory:'));
      repo.local.set('focusReminderUntil', repo.now + 3600000);
      await tester.pumpWidget(
        FocusNormsApp(repo: repo, folder: '.', backgroundEnabled: false),
      );
      expect(find.text('Показатели'), findsNothing);
      expect(find.text('Проекты'), findsNothing);
      await tester.tap(find.byTooltip('Норматив на день'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Создать работу'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Название'),
        'Чтение',
      );
      await tester.tap(find.text('Сохранить').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Помидорок за день · пусто для снятия'),
        '1',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('0/1'), findsWidgets);
      expect(repo.pomodoroTargetsForDate().length, 1);
      expect(repo.pending, isEmpty);
      await tester.tap(find.byTooltip('Фокус').first);
      await tester.pump();
      expect(repo.active?['title'], 'Чтение');
      expect(repo.pending, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
  testWidgets(
    'mobile player preserves pause and a long norm without layout errors',
    (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FocusRepository(LocalDatabase(':memory:'));
      final id = 'dc850236-d500-4acb-91af-61dabac79c6e',
          ref = 'work:dc850236-d500-4acb-91af-61dabac79c6e';
      repo.nativeSave('workspace', 'saveWorkItem', {
        'id': id,
        'create': true,
        'title': 'Регулярное чтение и применение новых идей',
        'description': '',
      }, ref);
      repo.nativeSave('pomodoroTarget', 'save', {
        'date': '2026-01-01',
        'workRef': ref,
        'title': 'Регулярное чтение и применение новых идей',
        'target': 2,
        'create': true,
      }, 'pomodoro:2026-01-01:$ref');
      await repo.focusWork(
        ref: ref,
        title: 'Регулярное чтение и применение новых идей',
      );
      await tester.pumpWidget(
        FocusNormsApp(repo: repo, folder: '.', backgroundEnabled: false),
      );
      expect(tester.takeException(), isNull);
      final pause = find.widgetWithText(FilledButton, 'Пауза');
      await tester.ensureVisible(pause);
      await tester.tap(pause);
      await tester.pump();
      expect(repo.active!['status'], 'paused');
      expect(find.text('Продолжить'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
}
