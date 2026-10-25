import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/adaptive_focus_player.dart';

void main() {
  for (final size in [const Size(340, 330), const Size(430, 430)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('day and week keep complete first text lines at $size / $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final changes = ChangeNotifier();
        addTearDown(changes.dispose);
        final week =
            'Неделя: ${List.filled(80, 'длинная формулировка').join(' ')} Конец-недели';
        const day =
            'Дневная проблема\n\n  Исходный текст с пробелами и абзацами.\nКонец-дня';
        var dayEdited = false;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('Pomodoro Club')),
              body: AdaptiveFocusPlayer(
                changes: changes,
                clock: '24:52',
                mode: 'Pomodoro',
                weeklyProblem: week,
                dailyProblem: day,
                editDailyProblem: () => dayEdited = true,
                contextPanel: const Text('Полный контекст'),
                description: const Text('Текущая работа'),
                actions: Wrap(
                  children: [
                    FilledButton(onPressed: () {}, child: const Text('Пауза')),
                    FilledButton(onPressed: () {}, child: const Text('Учесть')),
                  ],
                ),
                norms: const SizedBox(
                  height: 400,
                  child: Text('☐ Норматив — 0/1'),
                ),
                settings: const Text('Тема и звук'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Главная проблема недели').hitTestable(),
          findsOneWidget,
        );
        expect(
          find.text('Главная проблема на сегодня').hitTestable(),
          findsOneWidget,
        );
        for (final kind in ['week', 'day']) {
          final body = find.byKey(ValueKey('focus-problem-$kind-text'));
          final paragraph = tester.renderObject<RenderParagraph>(body);
          final box = paragraph
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 5),
              )
              .first
              .toRect();
          final firstWord = box.shift(paragraph.localToGlobal(Offset.zero));
          final viewport = tester.getRect(
            find.byKey(ValueKey('focus-problem-$kind-scroll')),
          );
          expect(firstWord.top, greaterThanOrEqualTo(viewport.top - .1));
          expect(firstWord.bottom, lessThanOrEqualTo(viewport.bottom + .1));
          expect(tester.widget<Text>(body).maxLines, isNull);
        }
        final dayBounds = tester.getRect(
          find.byKey(const ValueKey('focus-problem-day-scroll')),
        );
        await tester.drag(
          find.byKey(const ValueKey('focus-problem-week-scroll')),
          const Offset(0, -5000),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(
            find.byKey(const ValueKey('focus-problem-day-scroll')),
          ),
          dayBounds,
        );
        await tester.ensureVisible(find.text('24:52'));
        expect(find.text('24:52').hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.text('Учесть'));
        expect(find.text('Учесть').hitTestable(), findsOneWidget);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('focus-problem-day-text')),
              )
              .data,
          day,
        );
        await tester.ensureVisible(find.text('Главная проблема на сегодня'));
        await tester.tap(find.text('Главная проблема на сегодня'));
        expect(dayEdited, isTrue);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
