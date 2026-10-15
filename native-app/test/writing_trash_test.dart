import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/writing_screen.dart';

void main() {
  testWidgets(
    'delete preserves latest essay in offline queue and shows it in trash after reopening',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = LocalDatabase(':memory:');
      db.set('serverId', 'owner');
      db.capture('writing', {'instanceId': 'archive', 'entries': []});
      final repo = DashboardRepository(
        db,
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      Widget page() => MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          q.FlutterQuillLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(child: WritingScreen(repo: repo)),
        ),
      );
      await tester.pumpWidget(page());
      await tester.tap(find.text('Новая запись'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Удаляемая мысль');
      final editor = tester.widget<q.QuillEditor>(find.byType(q.QuillEditor));
      editor.controller.replaceText(
        0,
        0,
        'Последняя строка · 思考',
        const TextSelection.collapsed(offset: 0),
      );
      await tester.tap(find.text('Удалить запись'));
      await tester.pump();
      final command = object(repo.pending.single['body']);
      expect(command['action'], 'saveAndTrash');
      expect(
        rows(object(command['document'])['ops']).first['insert'],
        'Последняя строка · 思考\n',
      );
      expect(repo.writingEntries.single['trashedAt'], isNotNull);
      expect(editor.controller.readOnly, isTrue);
      await tester.tap(find.text('Корзина · 1'));
      await tester.pump();
      expect(find.text('Удаляемая мысль'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(page());
      await tester.tap(find.text('Корзина · 1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ListTile, 'Удаляемая мысль'));
      await tester.pump();
      final reopened = tester.widget<q.QuillEditor>(find.byType(q.QuillEditor));
      expect(
        reopened.controller.document.toPlainText(),
        'Последняя строка · 思考\n',
      );
      expect(reopened.controller.readOnly, isTrue);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Восстановить'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  test('restore uses current server revision; pending deletion cannot be overwritten', () {
    final db = LocalDatabase(':memory:');
    db.set('serverId', 'owner');
    const id = 'essay';
    final article = <String, dynamic>{
      'id': id,
      'title': 'Мысль',
      'date': today(),
      'status': 'draft',
      'revision': 2,
      'trashedAt': '2026-10-16T00:00:00Z',
      'document': {
        'ops': [
          {'insert': 'Текст\n'},
        ],
      },
    };
    db.capture('writing', {
      'instanceId': 'archive',
      'entries': [article],
    });
    db.capture('writing:$id', article);
    final repo = DashboardRepository(
      db,
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    repo.restoreWriting(id);
    final pending = object(repo.pending.single['body']);
    expect(pending['action'], 'restore');
    expect(pending['expectedRevision'], 2);
    expect(repo.writingEntries.single['trashedAt'], isNull);
    expect(() => repo.restoreWriting(id), throwsStateError);
    expect(object(repo.pending.single['body']), pending);
    // The failed connection is awaited before closing the repository below.
    addTearDown(() async {
      while (repo.syncing) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      repo.dispose();
    });
  });
}
