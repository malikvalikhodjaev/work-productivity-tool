import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/adaptive_focus_player.dart';
import 'package:indicators_work/focus_theme.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/section_analytics.dart';
import 'package:indicators_work/work_stage_board.dart';

void main() {
  test('writing aggregates chosen dates without trash or invented daily production', () {
    final result = writingWeekRows([
      {'date': '2026-10-19', 'words': 10},
      {
        'date': '2026-10-19',
        'favorite': true,
        'document': {
          'ops': [
            {'insert': '  мысль\nsecond  idea\n'},
          ],
        },
      },
      {'date': '2026-10-20', 'words': 200, 'trashedAt': 'stamp'},
      {'date': '2026-10-18', 'words': 99},
    ], '2026-10-19');
    expect(result.length, 7);
    expect(result.first['entries'], 2);
    expect(result.first['words'], 13);
    expect(result.first['favorite'], 1);
    expect(result[1]['entries'], 0);
  });
  for (final size in [
    const Size(430, 330),
    const Size(430, 718),
    const Size(1840, 900),
  ]) {
    testWidgets(
      'fixed timer remains usable at $size with long context and checklist',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final changes = ValueNotifier(0);
        addTearDown(changes.dispose);
        var paused = false;
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: boundary,
              child: FocusBackdrop(
                theme: 'monet',
                enabled: true,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(title: const Text('I&W · Фокус')),
                  body: AdaptiveFocusPlayer(
                    changes: changes,
                    clock: '24:48',
                    mode: 'Pomodoro',
                    contextPanel: const Text(
                      'Проблема недели и проблема дня · полный текст',
                    ),
                    description: Text(
                      List.filled(100, 'Длинное название работы').join(' '),
                    ),
                    actions: Wrap(
                      children: [
                        FilledButton(
                          onPressed: () => paused = true,
                          child: const Text('Пауза'),
                        ),
                        FilledButton(
                          onPressed: () {},
                          child: const Text('Учесть'),
                        ),
                      ],
                    ),
                    norms: Column(
                      children: [
                        for (var i = 0; i < 30; i++)
                          ListTile(title: Text('Норматив $i · 0/1')),
                      ],
                    ),
                    settings: const Text('Фоновый звук'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('24:48').hitTestable(), findsOneWidget);
        expect(find.text('Учесть').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Пауза'));
        expect(paused, isTrue);
        if (size.height < 620) {
          await tester.tap(find.byTooltip('Нормативы'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Норматив 29 · 0/1'),
            400,
            scrollable: find.byType(Scrollable).last,
          );
          expect(find.text('Норматив 29 · 0/1').hitTestable(), findsOneWidget);
          await tester.tap(find.byTooltip('Закрыть панель'));
          await tester.pumpAndSettle();
          expect(find.text('24:48').hitTestable(), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'stage collapse persists and never changes a card or case status',
    (tester) async {
      final db = LocalDatabase(':memory:');
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      final entry = {
        'item': {'title': 'Карточка'},
        'ref': 'work:one',
        'stage': 'active',
      };
      Widget board() => MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: repo,
            builder: (_, _) => SingleChildScrollView(
              child: WorkStageBoard(
                repo: repo,
                entries: [entry],
                card: (item, ref) => Text(item['title'].toString()),
                create: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(board());
      expect(find.text('Карточка'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('work-stage:active')));
      await tester.pump();
      expect(find.text('Карточка'), findsNothing);
      expect(db.get('workStageCollapsed')['active'], isTrue);
      expect(entry['stage'], 'active');
      expect(caseStage({'status': 'watching'}), 'active');
      expect(caseStage({'status': 'closed'}), 'ready');
    },
  );
}
