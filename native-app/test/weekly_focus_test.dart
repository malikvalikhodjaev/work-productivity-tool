import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/compact_timer.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/focus_viewport.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/weekly_problem_card.dart';

void main() {
  test('week boundaries and offline projection retain exact text and original version', () {
    expect(weekStart('2026-10-25'), '2026-10-19');
    expect(weekStart('2027-01-01'), '2026-12-28');
    final db = LocalDatabase(':memory:');
    db.set('serverId', 'owner-server');
    db.set('automaticSync', false);
    final repo = DashboardRepository(db);
    addTearDown(repo.dispose);
    final week = weekStart();
    repo.saveWeeklyProblem(week, '  中文\nПервый разрыв  ');
    expect(repo.weeklyProblemText, '  中文\nПервый разрыв  ');
    db.capture('weeklyProblems', {
      'entries': [
        {'week': week, 'text': 'С другого устройства', 'updatedAt': 'v2'},
      ],
    });
    expect(repo.weeklyProblemText, '  中文\nПервый разрыв  ');
    repo.saveWeeklyProblem(week, 'Уточнённый разрыв');
    expect(repo.pending.length, 1);
    expect(repo.pending.single['body']['input']['expectedUpdatedAt'], null);
    expect(repo.weeklyProblemText, 'Уточнённый разрыв');
    expect(repo.todayProblem, isEmpty);
  });
  test('acknowledgement captures the weekly snapshot before removing the local draft', () async {
    final db = LocalDatabase(':memory:');
    db.set('serverId', 'owner-server');
    db.set('automaticSync', false);
    final week = weekStart();
    final repo = DashboardRepository(
      db,
      client: MockClient((request) async {
        if (request.url.path == '/api/offline/connect') {
          return http.Response(jsonEncode({'serverId': 'owner-server'}), 200);
        }
        if (request.url.path == '/api/native/command') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'weeklyProblems': {
                  'entries': [
                    {
                      'week': week,
                      'text': 'Проверить результат',
                      'updatedAt': 'v1',
                      'revisions': [],
                    },
                  ],
                },
              }),
            ),
            200,
          );
        }
        return http.Response(
          '{}',
          503,
        ); // A later poll fails after the command was committed.
      }),
    );
    addTearDown(repo.dispose);
    repo.saveWeeklyProblem(week, 'Проверить результат');
    await repo.synchronize();
    expect(repo.pending, isEmpty);
    expect(db.draft('weeklyProblem:$week'), null);
    expect(repo.weeklyProblemText, 'Проверить результат');
  });
  testWidgets(
    'weekly history is separate and the original reference stays collapsed',
    (tester) async {
      final db = LocalDatabase(':memory:');
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      db.capture('weeklyProblems', {
        'entries': [
          {'week': '2020-01-06', 'text': 'Прошлый разрыв', 'revisions': []},
        ],
      });
      db.capture('references', {
        'entries': [
          {
            'title': 'Marc Andreessen · главная проблема недели',
            'originalText': 'Private reference text',
          },
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeeklyProblemCard(repo: repo, edit: (_) async {}),
            ),
          ),
        ),
      );
      expect(find.text('No Data'), findsOneWidget);
      expect(find.text('Private reference text').hitTestable(), findsNothing);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2020-01-06 — 2020-01-12').last);
      await tester.pumpAndSettle();
      expect(find.text('Прошлый разрыв'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'focus width is bounded and all content is reachable in a short window',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1840, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = newLocalSession(
        title: 'Длинное название работы ' * 12,
        workRef: 'case:one',
        now: DateTime.now().millisecondsSinceEpoch,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FocusViewport(
              child: CompactTimer(
                session: session,
                now: DateTime.now().millisecondsSinceEpoch,
                theme: 'green',
                pause: () {},
                finish: () {},
                checklist: const SizedBox(
                  height: 800,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text('Последний норматив'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('focus-readable-column')))
            .width,
        560,
      );
      tester.view.physicalSize = const Size(430, 330);
      await tester.pump();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('focus-readable-column')))
            .width,
        406,
      );
      await tester.scrollUntilVisible(
        find.text('Учесть'),
        160,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      expect(find.text('Учесть').hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Последний норматив'),
        220,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      expect(find.text('Последний норматив').hitTestable(), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
}
