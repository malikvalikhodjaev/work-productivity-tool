import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/section_analytics.dart';

void main() {
  test('analytics deduplicates synced sessions and splits local time at Tashkent midnight', () {
    final db = LocalDatabase(':memory:');
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    final start = DateTime.parse('2026-10-19T18:50:00Z').millisecondsSinceEpoch;
    db.capture('entries', {
      'entries': [
        {
          'id': 'entry',
          'date': '2026-10-19',
          'timerSessionId': 'synced',
          'durationSeconds': 600,
        },
      ],
    });
    db.capture('timer', {
      'sessions': [
        {
          'id': 'synced',
          'status': 'finished',
          'phase': 'work',
          'intervals': [
            {'start': start, 'end': start + 600000},
          ],
        },
        {
          'id': 'local',
          'status': 'finished',
          'phase': 'work',
          'intervals': [
            {'start': start, 'end': start + 1200000},
          ],
        },
        {
          'id': 'active',
          'status': 'running',
          'phase': 'work',
          'intervals': [
            {'start': start, 'end': start + 1200000},
          ],
        },
      ],
    });
    final entries = analyticsTimeRows(repo);
    expect(entries.length, 3);
    expect(
      entries.where((e) => e['date'] == '2026-10-20').single['durationSeconds'],
      600,
    );
    expect(
      entries.fold<num>(0, (s, e) => s + (e['durationSeconds'] as num)),
      1800,
    );
  });
  testWidgets(
    'indicators contains goals and norms without the work timer or systems section',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = LocalDatabase(':memory:');
      db.set('automaticSync', false);
      final repo = DashboardRepository(
        db,
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      db.capture('workspace', {
        'goals': [
          {
            'id': 'g',
            'title': 'Цель А',
            'status': 'active',
            'parentId': null,
            'unit': 'шт',
          },
        ],
      });
      await tester.pumpWidget(
        DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
      );
      await tester.pump();
      expect(find.text('Цели'), findsOneWidget);
      expect(find.text('Все цели · декомпозиция'), findsOneWidget);
      expect(find.text('Главная проблема недели'), findsNothing);
      expect(find.text('Pomodoro'), findsNothing);
      expect(find.text('Финансовый поток'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Нормативы'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Нормативы').hitTestable(), findsOneWidget);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
  testWidgets(
    'goal tree shows own measurements and supports adding a subgoal',
    (tester) async {
      Json? parent;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GoalHierarchy(
                goals: [
                  {
                    'id': 'parent',
                    'title': 'Основная',
                    'current': 2,
                    'target': 10,
                    'percent': 20,
                  },
                  {
                    'id': 'child',
                    'parentId': 'parent',
                    'title': 'Шаг',
                    'current': 8,
                    'target': 10,
                    'percent': 80,
                  },
                ],
                edit: (_) {},
                measure: (_) {},
                child: (g) => parent = g,
              ),
            ),
          ),
        ),
      );
      expect(find.text('1.1 · Шаг'), findsOneWidget);
      await tester.tap(find.text('＋ Подцель').first);
      expect(parent?['id'], 'parent');
      expect(tester.takeException(), null);
    },
  );
}
