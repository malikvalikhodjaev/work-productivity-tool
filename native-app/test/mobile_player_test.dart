import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/project_review.dart';

LocalDatabase database() {
  final db = LocalDatabase(':memory:');
  db.set('serverId', 'owner-server');
  db.capture('timer', {
    'revision': 0,
    'active': null,
    'settings': timerDefaults,
  });
  db.capture('workspace', {
    'cases': [
      {'id': 'one', 'title': 'Моя работа', 'status': 'active'},
    ],
    'entities': [
      {'ref': 'case:one', 'title': 'Моя работа'},
    ],
  });
  return db;
}

DashboardRepository repository(LocalDatabase db, List<Json> commands) =>
    DashboardRepository(
      db,
      client: MockClient((r) async {
        if (r.url.path == '/api/offline/connect') {
          return http.Response(jsonEncode({'serverId': 'owner-server'}), 200);
        }
        final command = object(jsonDecode(r.body));
        commands.add(command);
        final input = object(command['input']);
        final active = command['action'] == 'start'
            ? newLocalSession(
                title: input['title'],
                workRef: input['workRef'],
                now: DateTime.now().millisecondsSinceEpoch,
              )
            : changeLocalSession(
                object(db.snapshot('timer')['active']),
                command['action'],
                DateTime.now().millisecondsSinceEpoch,
              );
        return http.Response(
          jsonEncode({
            'revision': (db.snapshot('timer')['revision'] as int) + 1,
            'active': active,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..online = true;

Future<void> openWork(WidgetTester tester, DashboardRepository repo) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
  );
  await tester.tap(find.text('Работа').last);
  await tester.pump();
}

void main() {
  test(
    'daily problem uses today and saved local edits, preserving the text',
    () {
      final db = database();
      final repo = DashboardRepository(db);
      addTearDown(repo.dispose);
      expect(repo.todayProblemText, startsWith('No Data'));
      db.capture('problems', {
        'entries': [
          {'date': '2020-01-01', 'text': 'Старая проблема'},
        ],
      });
      expect(repo.todayProblemText, 'Главная проблема на сегодня не записана');
      db.capture('problems', {
        'entries': [
          {'date': today(), 'text': 'Сегодня: важное'},
        ],
      });
      expect(repo.todayProblemText, 'Сегодня: важное');
      db.keepDraft('problem:${today()}', {
        'date': today(),
        'text': '  Моё уточнение · 思考  ',
      });
      expect(repo.todayProblemText, '  Моё уточнение · 思考  ');
    },
  );

  testWidgets(
    'phone play opens the player at the top with the daily problem above its clock',
    (tester) async {
      final db = database();
      db.capture('problems', {
        'entries': [
          {'date': today(), 'text': 'Главный разрыв сегодня'},
        ],
      });
      final commands = <Json>[];
      final repo = repository(db, commands);
      await openWork(tester, repo);
      await tester.ensureVisible(
        find.widgetWithText(TextButton, 'Фокус').first,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Фокус').first);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byTooltip('Все разделы'), findsOneWidget);
      expect(find.text('Главный разрыв сегодня'), findsOneWidget);
      final banner = find.byKey(const ValueKey('daily-problem-above-timer'));
      expect(tester.getTopLeft(banner).dy, greaterThanOrEqualTo(0));
      expect(
        tester.getBottomLeft(banner).dy,
        lessThan(tester.getTopLeft(find.byType(FittedBox)).dy),
      );
      expect(repo.active?['workRef'], 'case:one');
      expect(commands, hasLength(1));
      await tester.tap(find.byTooltip('Все разделы'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(TextButton, 'Фокус').first,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Фокус').first);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(commands, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  testWidgets(
    'a new named activity opens its player after the form closes; empty problem is explicit',
    (tester) async {
      final db = database();
      db.capture('problems', {'entries': []});
      final repo = repository(db, []);
      await openWork(tester, repo);
      await tester.ensureVisible(find.text('Новая активность'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новая активность'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Что делаю',
        ),
        'Свободная работа',
      );
      await tester.ensureVisible(find.text('▶ Запустить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('▶ Запустить'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        find.text('Главная проблема на сегодня не записана'),
        findsOneWidget,
      );
      expect(repo.active?['title'], 'Свободная работа');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  testWidgets(
    'failed play stays on the work screen without opening an empty player',
    (tester) async {
      final db = database();
      final repo = repository(db, [])..online = false;
      await openWork(tester, repo);
      await tester.ensureVisible(
        find.widgetWithText(TextButton, 'Фокус').first,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Фокус').first);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(repo.active, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  test(
    'project review shows known gaps and due dates without changing records',
    () {
      final projects = <Json>[
        {
          'id': 'one',
          'name': 'Проект',
          'status': 'active',
          'zones': [
            {
              'title': 'Клиенты',
              'covered': false,
              'issues': ['не обсуждено'],
            },
          ],
        },
        {'id': 'closed', 'status': 'closed'},
      ];
      final alphas = <Json>[
        {
          'id': 'alpha',
          'projectId': 'one',
          'typeName': 'Команда',
          'uniqueName': '',
          'evidence': '',
          'nextStep': '',
          'reviewDate': '2026-10-15',
        },
        {
          'id': 'later',
          'projectId': 'one',
          'typeName': 'Продукт',
          'uniqueName': 'Мой продукт',
          'evidence': 'Проверено',
          'nextStep': 'Показать',
          'reviewDate': '2026-10-20',
        },
      ];
      final raw = jsonEncode([projects, alphas]);
      final review = reviewProjects(projects, alphas, '2026-10-15');
      expect(review, hasLength(1));
      expect(review.single['zones'], ['Клиенты: не обсуждено']);
      expect(rows(review.single['alphas']).first['due'], true);
      expect(rows(review.single['alphas']).last['due'], false);
      expect(rows(review.single['alphas']).last['reasons'], isEmpty);
      expect(jsonEncode([projects, alphas]), raw);
    },
  );
}
