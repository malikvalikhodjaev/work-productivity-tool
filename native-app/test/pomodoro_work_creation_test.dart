import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/pomodoro_widgets.dart';
import 'package:indicators_work/repository.dart';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<void> openEditor(WidgetTester tester, DashboardRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => editPomodoroTarget(context, repo),
            child: const Text('Норматив на день'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Норматив на день'));
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in ['work', 'case']) {
    testWidgets('create $kind and assign a norm offline from an empty list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = LocalDatabase(':memory:');
      db.set('serverId', 'owner');
      db.capture('workspace', {'entities': [], 'workItems': [], 'cases': []});
      final repo = DashboardRepository(
        db,
        client: MockClient(
          (_) async => http.Response(jsonEncode({'error': 'Offline'}), 503),
        ),
      );
      await openEditor(tester, repo);
      expect(find.text('Создай работу или кейс'), findsOneWidget);
      await tester.enterText(field('Действует с · YYYY-MM-DD'), '2026-10-16');
      await tester.enterText(
        field('Помидорок за день · пусто для снятия'),
        '10',
      );
      await tester.tap(find.text('Создать работу / кейс'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Название: от 1'), findsOneWidget);
      expect(repo.pending, isEmpty);
      if (kind == 'case') {
        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Кейс').last);
        await tester.pumpAndSettle();
      }
      await tester.enterText(field('Название'), 'Моделировать систему · 模型');
      await tester.enterText(
        field('Описание и размышления'),
        'Первая заметка\nВторая строка',
      );
      await tester.tap(find.text('Сохранить').last);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Моделировать систему · 模型'), findsWidgets);
      expect(
        tester
            .widget<TextField>(field('Действует с · YYYY-MM-DD'))
            .controller!
            .text,
        '2026-10-16',
      );
      expect(
        tester
            .widget<TextField>(field('Помидорок за день · пусто для снятия'))
            .controller!
            .text,
        '10',
      );
      await tester.enterText(field('Название норматива'), '  Моя норма  ');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.pending, hasLength(2));
      final create = object(repo.pending.first['body']);
      expect(create['action'], kind == 'case' ? 'saveCase' : 'saveWorkItem');
      final created = repo
          .entities(kind == 'case' ? 'cases' : 'workItems', kind)
          .single;
      expect(created['title'], 'Моделировать систему · 模型');
      expect(
        created[kind == 'case' ? 'context' : 'description'],
        'Первая заметка\nВторая строка',
      );
      final plan = repo.pomodoroTargetsForDate('2026-10-16').single;
      expect(plan['workRef'], '$kind:${created['id']}');
      expect(plan['title'], '  Моя норма  ');
      expect(plan['target'], 10);
      expect(plan['actualPomodoros'], 0);
      expect(object(repo.pending.last['body'])['module'], 'pomodoroTarget');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    });
  }

  testWidgets(
    'adding a second norm preserves the first and rejects accidental replacement',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = LocalDatabase(':memory:')
        ..set('serverId', 'owner')
        ..set('automaticSync', false);
      db.capture('workspace', {
        'entities': [
          {'ref': 'work:first', 'title': 'ИТ решение'},
          {'ref': 'work:second', 'title': 'Руководства'},
        ],
      });
      db.capture('dailyNorms', {
        'pomodoroTargets': [
          {
            'date': today(),
            'repeat': 'daily',
            'workRef': 'work:first',
            'title': 'Первая норма',
            'target': 10,
          },
        ],
      });
      final repo = DashboardRepository(db);
      await openEditor(tester, repo);
      expect(find.text('Выбери работу'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ИТ решение').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.textContaining('уже есть норматив'), findsOneWidget);
      expect(repo.pending, isEmpty);
      expect(repo.pomodoroTargetsForDate().single['title'], 'Первая норма');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Руководства').last);
      await tester.pumpAndSettle();
      await tester.enterText(field('Название норматива'), 'Вторая норма');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(repo.pomodoroTargetsForDate().map((n) => n['title']), [
        'Первая норма',
        'Вторая норма',
      ]);
      expect(
        object(object(repo.pending.single['body'])['input'])['create'],
        true,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
  testWidgets('cancel creation preserves the existing norm form on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = LocalDatabase(':memory:');
    db.set('serverId', 'owner');
    db.capture('workspace', {
      'entities': [
        {'ref': 'work:existing', 'title': 'Моя работа'},
      ],
    });
    final repo = DashboardRepository(
      db,
      client: MockClient(
        (_) async => http.Response('{"error":"Offline"}', 503),
      ),
    );
    await openEditor(tester, repo);
    await tester.enterText(field('Название норматива'), 'Свой текст');
    await tester.enterText(field('Помидорок за день · пусто для снятия'), '3');
    await tester.tap(find.text('Создать работу / кейс'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Закрыть').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('Название норматива')).controller!.text,
      'Свой текст',
    );
    expect(
      tester
          .widget<TextField>(field('Помидорок за день · пусто для снятия'))
          .controller!
          .text,
      '3',
    );
    expect(repo.pending, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
  });
}
