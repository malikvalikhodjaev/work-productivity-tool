import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/systems_panel.dart';

void main() {
  testWidgets(
    'an unconfigured system explains its purpose and offers a concrete setup action',
    (tester) async {
      final repo = DashboardRepository(
        LocalDatabase(':memory:')
          ..set('automaticSync', false)
          ..capture('workspace', {
            'systems': [
              {
                'id': 's',
                'name': 'Моя система',
                'characteristics': [
                  {
                    'id': 'c',
                    'name': '',
                    'unit': '',
                    'current': null,
                    'target': null,
                  },
                ],
              },
            ],
          }),
      );
      addTearDown(repo.dispose);
      String? configured;
      var work = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SystemsPanel(
                repo: repo,
                configure: (s) => configured = s?['id'],
                measure: (_, _) {},
                openWork: () => work = true,
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('No Data'), findsNothing);
      expect(
        find.textContaining('Характеристики ещё не выбраны'),
        findsOneWidget,
      );
      expect(find.textContaining('Чтобы появились данные'), findsOneWidget);
      await tester.tap(find.text('Настроить характеристики'));
      expect(configured, 's');
      await tester.tap(find.text('Перейти к работам'));
      expect(work, true);
      expect(repo.pending, isEmpty);
    },
  );
  testWidgets(
    'a characteristic offers a first measurement and displays its offline projection',
    (tester) async {
      final characteristic = <String, dynamic>{
        'id': 'c',
        'name': 'Полезные изменения',
        'unit': 'шт.',
        'kind': 'priority',
        'target': 10,
      };
      final repo = DashboardRepository(
        LocalDatabase(':memory:')
          ..set('serverId', 'owner')
          ..set('automaticSync', false)
          ..capture('workspace', {
            'systems': [
              {
                'id': 's',
                'name': 'Моя система',
                'characteristics': [characteristic],
              },
            ],
            'measurements': [],
          }),
      );
      addTearDown(repo.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: repo,
                builder: (context, _) => SystemsPanel(
                  repo: repo,
                  configure: (_) {},
                  measure: (s, c) => repo.recordGoalMeasurement(
                    {...c, 'characteristicId': c['id']},
                    5,
                    evidence: '  raw\n text  ',
                  ),
                  openWork: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('Замеров пока нет — запиши первое значение.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Записать первый замер'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Записать первый замер'));
      await tester.pumpAndSettle();
      expect(find.text('Сейчас: 5 шт.'), findsOneWidget);
      final input = object(object(repo.pending.single['body'])['input']);
      expect(input['kind'], 'characteristic');
      expect(input['targetId'], 'c');
      expect(input['evidence'], '  raw\n text  ');
      expect(find.textContaining('No Data'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a missing unit leads to setup instead of queuing a meaningless value',
    (tester) async {
      final repo = DashboardRepository(
        LocalDatabase(':memory:')
          ..set('automaticSync', false)
          ..capture('workspace', {
            'systems': [
              {
                'id': 's',
                'name': 'Система',
                'characteristics': [
                  {'id': 'c', 'name': 'Темп', 'unit': ''},
                ],
              },
            ],
          }),
      );
      addTearDown(repo.dispose);
      var configured = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SystemsPanel(
                repo: repo,
                configure: (_) => configured = true,
                measure: (_, _) => fail('measurement must not be queued'),
                openWork: () {},
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('Для замера сначала укажи единицу в настройках.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Уточнить характеристику'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Уточнить характеристику'));
      expect(configured, true);
      expect(repo.pending, isEmpty);
    },
  );
}
