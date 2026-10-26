import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/goal_table.dart';
import 'package:indicators_work/inline_cell.dart';

Json goal() => {
  'id': 'g',
  'title': 'Мастерство',
  'unit': 'ч',
  'status': 'active',
  'direction': 'up',
  'updatedAt': 'old',
  'baseline': null,
  'target': null,
};
LocalDatabase database() => LocalDatabase(':memory:')
  ..set('serverId', 'test')
  ..set('automaticSync', false)
  ..capture('workspace', {
    'goals': [goal()],
    'goalGridVersion': 1,
    'goalFieldEditingVersion': 1,
    'goalTextLimits': {'unit': 200},
  });

class RecoveryRepository extends DashboardRepository {
  Json fresh;
  int reads = 0;
  RecoveryRepository(super.local, this.fresh);
  @override
  Future<Json> request(String route, {Json? body}) async {
    reads++;
    return fresh;
  }
}

void main() {
  test('type column remains between name and system and explicit rename conflict uses its advertised definition', () async {
    final db = database()
      ..capture('workspace', {
        'goalGridVersion': 1,
        'goalColumnDefinitions': [
          {'id': 'title', 'title': 'Моё название', 'type': 'text'},
          {
            'id': 'physicalSystem',
            'title': 'Физическая система',
            'type': 'text',
          },
        ],
        'characteristicColumnDefinitions': [
          {
            'id': 'characteristicType',
            'title': 'Тип',
            'revision': 0,
            'type': 'select',
          },
        ],
      });
    final repo = RecoveryRepository(db, {
      'goalColumnDefinitions': [],
      'characteristicColumnDefinitions': [
        {
          'id': 'characteristicType',
          'title': 'Новое название',
          'revision': 2,
          'type': 'select',
        },
      ],
    });
    addTearDown(repo.dispose);
    expect(repo.goalColumns().map((c) => c['id']), [
      'title',
      'characteristicType',
      'physicalSystem',
    ]);
    expect(repo.goalColumns().first['title'], 'Моё название');
    repo.goalGridCommand('updateGoalColumn', {
      'id': 'characteristicType',
      'title': 'Вид',
      'expectedRevision': 0,
    });
    final command = repo.pending.single;
    db.attempted(command['id'].toString());
    db.conflict(command['id'].toString(), 'Название изменено');
    await repo.resolveConflict(db.queue.single, apply: true);
    expect(
      object(object(repo.pending.single['body'])['input'])['expectedRevision'],
      2,
    );
  });
  test('editing another cell and the same cell preserves attempted commands and queues ordered independent patches', () {
    final repo = DashboardRepository(database());
    addTearDown(repo.dispose);
    repo.editGoalField('g', 'title', '  Новое имя  ');
    final first = repo.pending.single, raw = jsonEncode(first['body']);
    repo.local.attempted(first['id'].toString());
    repo.editGoalField(
      'g',
      'unit',
      'кол-во времени вложенного в работу в неделю',
    );
    repo.editGoalField('g', 'title', '  Ещё одно имя  ');
    expect(repo.pending, hasLength(3));
    expect(jsonEncode(repo.pending.first['body']), raw);
    expect(object(object(repo.pending.last['body'])['input'])['changes'], [
      {
        'field': 'title',
        'before': '  Новое имя  ',
        'value': '  Ещё одно имя  ',
      },
    ]);
    expect(
      repo.entities('goals', 'goal').single['unit'],
      'кол-во времени вложенного в работу в неделю',
    );
    final rowsBefore = repo.pending.length;
    expect(
      () => repo.editGoalField('g', 'unit', 'я' * 201),
      throwsFormatException,
    );
    expect(repo.pending, hasLength(rowsBefore));
    repo.editGoalField('g', 'characteristicType', 'guardrail');
    expect(
      repo.entities('goals', 'goal').single['characteristicType'],
      'guardrail',
    );
    repo.undoGoalField();
    expect(repo.entities('goals', 'goal').single['characteristicType'], isNull);
  });
  test('form save sends only changed fields using its opening snapshot', () {
    final repo = DashboardRepository(database());
    addTearDown(repo.dispose);
    final before = goal();
    repo.local.capture('workspace', {
      'goals': [
        {...before, 'unit': 'дни'},
      ],
      'goalGridVersion': 1,
      'goalFieldEditingVersion': 1,
    });
    repo.nativeSave(
      'workspace',
      'saveGoal',
      {...before, 'title': 'Имя из формы'},
      'goal:g',
      expectedEntity: before,
      expectedUpdatedAt: 'old',
    );
    expect(object(object(repo.pending.single['body'])['input'])['changes'], [
      {'field': 'title', 'before': 'Мастерство', 'value': 'Имя из формы'},
    ]);
    expect(repo.entities('goals', 'goal').single['unit'], 'дни');
  });
  test('old unit validation retries the identical command only after advertised server support; drafts stay raw', () async {
    final db = database();
    final id = db.enqueue(
      'goal:g',
      '/api/native/command',
      {
        'requestId': uuid.v4(),
        'serverId': 'test',
        'deviceId': 'device',
        'module': 'workspace',
        'action': 'saveGoal',
        'expectedUpdatedAt': 'old',
        'input': {...goal(), 'unit': 'кол-во времени вложенного в работу'},
      },
      draft: {...goal(), 'unit': 'кол-во времени вложенного в работу'},
    );
    db.attempted(id);
    db.conflict(id, 'Единица: не больше 30 символов.');
    db.set('goalInline:test:g:unit', {
      'text': '  полный текст в неделю  ',
      'base': goal(),
    });
    final raw = jsonEncode(db.queue.single['body']),
        draft = jsonEncode(db.get('goalInline:test:g:unit'));
    final repo = RecoveryRepository(db, {
      'goals': [goal()],
      'goalTextLimits': {'unit': 30},
    });
    addTearDown(repo.dispose);
    await repo.recoverLegacyGoalValidation();
    expect(db.queue.single['state'], 'conflict');
    repo.fresh = {
      'goals': [goal()],
      'goalTextLimits': {'unit': 200},
      'goalFieldEditingVersion': 1,
    };
    await repo.recoverLegacyGoalValidation();
    expect(db.queue.single['state'], 'queued');
    expect(db.queue.single['attempted'], 1);
    expect(db.queue.single['id'], id);
    expect(jsonEncode(db.queue.single['body']), raw);
    expect(jsonEncode(db.get('goalInline:test:g:unit')), draft);
    expect(
      rows(db.get('goalValidationReplayHistory')).single['commandChanged'],
      false,
    );
    await repo.recoverLegacyGoalValidation();
    expect(repo.reads, 2);
  });
  testWidgets('type is a selectable field with no invented default', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = DashboardRepository(database());
    addTearDown(repo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: repo,
              builder: (_, _) => GoalsTable(
                repo: repo,
                goals: repo.entities('goals', 'goal'),
                edit: (_) {},
                measure: (_) {},
                child: (_) {},
                history: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.entities('goals', 'goal').single['characteristicType'], isNull);
    await tester.tap(find.byKey(const ValueKey('characteristic-type:g:null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мониторинг').last);
    await tester.pumpAndSettle();
    expect(
      repo.entities('goals', 'goal').single['characteristicType'],
      'monitoring',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'inline validation is readable in full and never exposes Bad state prefix',
    (tester) async {
      const message =
          'Эта правка ожидает подтверждения. Введённый текст сохранён на устройстве и не будет потерян. Проверь статус синхронизации.';
      String retained = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 180,
                child: InlineCell(
                  text: 'До',
                  label: 'Единица измерения',
                  retain: (v) => retained = v,
                  commit: (_) async => throw StateError(message),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('До'));
      await tester.pump();
      await tester.enterText(
        find.byType(TextField),
        'кол-во времени вложенного в работу в неделю',
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('Bad state:'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('inline-cell-error')))
            .maxLines,
        isNull,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('inline-cell-error'))).height,
        greaterThan(40),
      );
      expect(retained, 'кол-во времени вложенного в работу в неделю');
      expect(tester.takeException(), isNull);
    },
  );
}
