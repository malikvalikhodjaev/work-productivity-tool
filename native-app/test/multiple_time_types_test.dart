import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/forms.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/pomodoro_widgets.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/time_composition.dart';
import 'package:indicators_work/time_composition_panel.dart';

void main() {
  test(
    'combined types retain canonical identity and reject invalid selections',
    () {
      expect(timeType('productive+investment'), 'investment+productive');
      expect(timeTypeLabel('investment+productive'), 'Investment + Productive');
      expect(validTimeTypeSelection('investment+productive'), true);
      for (final value in [
        'investment+investment',
        'productive+other',
        'unclassified',
        null,
      ]) {
        expect(validTimeTypeSelection(value), false);
      }
    },
  );
  testWidgets(
    'norm saves two types, appears in both filters and starts one session',
    (tester) async {
      final db = LocalDatabase(':memory:')
        ..set('serverId', 'demo')
        ..set('automaticSync', false)
        ..set('timerStrategy', 'local');
      db.capture('workspace', {
        'entities': [
          {
            'ref': 'work:a',
            'title': 'Разработать инструмент',
            'workType': 'productive',
          },
        ],
      });
      db.capture('dailyNorms', {
        'pomodoroTargets': [
          {
            'date': today(),
            'repeat': 'daily',
            'workRef': 'work:a',
            'title': 'Разработать инструмент',
            'target': 2,
            'workType': 'investment',
          },
        ],
      });
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => editPomodoroTarget(
                  context,
                  repo,
                  previous: repo.pomodoroTargetsForDate().single,
                ),
                child: const Text('Править'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Править'));
      await tester.pumpAndSettle();
      final second = find.byKey(const ValueKey('time-type:productive'));
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pump();
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('time-type:investment')),
            )
            .selected,
        true,
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(
        repo.pomodoroTargetsForDate().single['workType'],
        'investment+productive',
      );
      expect(
        object(repo.pending.single['body'])['input']['workType'],
        'investment+productive',
      );
      await repo.focusWork(ref: 'work:a', title: 'Разработать инструмент');
      final session = Map<String, dynamic>.from(repo.active!);
      expect(session['workType'], 'investment+productive');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: PomodoroChecklist(repo: repo)),
          ),
        ),
      );
      for (final filter in ['investment', 'productive']) {
        await tester.tap(find.byKey(ValueKey('norm-filter:$filter')));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('pomodoro-row:work:a')),
          findsOneWidget,
        );
        expect(repo.pomodoroTargetsForDate().length, 1);
        expect(repo.active, session);
      }
      await tester.tap(find.byKey(const ValueKey('norm-filter:leisure')));
      await tester.pump();
      expect(find.byKey(const ValueKey('pomodoro-row:work:a')), findsNothing);
      expect(find.text('Показать активный норматив'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'work editor preserves existing combination and raw text when toggling types',
    (tester) async {
      Json? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => editFields(
                  context,
                  title: 'Работа',
                  initial: {
                    'workType': 'investment+productive',
                    'title': '  Точный\nтекст  ',
                  },
                  fields: const [
                    FieldSpec('workType', 'Типы времени', timeTypes: true),
                    FieldSpec('title', 'Название', lines: 2),
                  ],
                  save: (value) async {
                    saved = value;
                  },
                ),
                child: const Text('Править'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Править'));
      await tester.pumpAndSettle();
      for (final kind in ['investment', 'productive']) {
        expect(
          tester
              .widget<FilterChip>(find.byKey(ValueKey('time-type:$kind')))
              .selected,
          true,
        );
      }
      await tester.tap(find.byKey(const ValueKey('time-type:leisure')));
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(saved!['workType'], 'investment+productive+leisure');
      expect(saved!['title'], '  Точный\nтекст  ');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('composition counts mixed sessions once and renders mixed bars', (
    tester,
  ) async {
    final entries = <Json>[
      {
        'durationSeconds': 1500,
        'workType': 'productive+investment',
        'timerSessionId': 'mixed',
      },
      {
        'durationSeconds': 1500,
        'workType': 'leisure',
        'timerSessionId': 'rest',
      },
    ];
    final facts = <Json>[
      {'sessionId': 'mixed'},
      {'sessionId': 'mixed'},
    ];
    final sessions = <String, Json>{
      'mixed': {'workType': 'investment+productive'},
    };
    final result = timeComposition(entries, facts, sessions);
    final mixed = result.singleWhere(
      (r) => r['type'] == 'investment+productive',
    );
    expect(mixed['seconds'], 1500);
    expect(mixed['pomodoros'], 1);
    expect(mixed['percent'], 50);
    expect(mixed['pomodoroPercent'], 100);
    expect(result.fold<double>(0, (n, r) => n + r['seconds']), 3000);
    expect(result.fold<int>(0, (n, r) => n + (r['pomodoros'] as int)), 1);
    expect(result.fold<double>(0, (n, r) => n + (r['percent'] as double)), 100);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TimeCompositionPanel(
              entries: entries,
              facts: facts,
              sessions: sessions,
              days: const [],
              known: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Investment + Productive'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
