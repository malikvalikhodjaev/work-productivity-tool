import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/inbox_widget.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';
import 'package:indicators_work/writing_screen.dart';

Widget page(Widget body) => MaterialApp(
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    q.FlutterQuillLocalizations.delegate,
  ],
  home: Scaffold(body: SingleChildScrollView(child: body)),
);
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  test('acknowledged favorite metadata wins over an older composer draft', () {
    final db = LocalDatabase(':memory:');
    db.capture('writing', {
      'entries': [
        {'id': 'essay', 'favorite': true, 'revision': 2, 'trashedAt': null},
      ],
    });
    db.capture('writing:essay', {
      'id': 'essay',
      'favorite': true,
      'revision': 2,
      'trashedAt': null,
    });
    db.keepDraft('composer:essay', {
      'id': 'essay',
      'favorite': false,
      'title': 'Мой локальный текст',
    });
    final repo = DashboardRepository(db);
    expect(repo.writingEntries.single['favorite'], true);
    expect(repo.writingEntries.single['title'], 'Мой локальный текст');
    repo.dispose();
  });
  testWidgets(
    'favorite essay appears in its filter and can be unstarred before network sync',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = LocalDatabase(':memory:');
      db.set('serverId', 'owner');
      db.set('automaticSync', false);
      db.capture('writing', {'instanceId': 'archive', 'entries': []});
      final repo = DashboardRepository(db);
      await tester.pumpWidget(page(WritingScreen(repo: repo)));
      await tester.tap(find.text('Новая запись'));
      await tester.pump();
      await tester.enterText(field('Тема записи'), 'Вернуться к этой мысли');
      await tester.tap(find.text('В избранное'));
      await tester.pump();
      expect(repo.writingEntries.single['favorite'], true);
      await tester.tap(find.text('Избранное · 1'));
      await tester.pump();
      expect(
        find.widgetWithText(ListTile, 'Вернуться к этой мысли'),
        findsOneWidget,
      );
      await tester.tap(find.text('В избранном'));
      await tester.pump();
      expect(repo.writingEntries.single['favorite'], false);
      expect(repo.pending.length, 1);
      expect(object(repo.pending.single['body'])['favorite'], false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  testWidgets(
    'multiline note can be starred and processed into archive entirely offline',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = LocalDatabase(':memory:');
      db.set('serverId', 'owner');
      db.set('automaticSync', false);
      final item = <String, dynamic>{
        'id': 'note',
        'title': 'telegram-note (16.10.2026 21:08)',
        'kind': 'text',
        'body': 'Первая строка\nВторая строка',
        'sourceText': 'Первая строка\nВторая строка',
        'notes': '',
        'transcript': '',
        'status': 'new',
        'updatedAt': '2026-10-16T00:00:00Z',
      };
      db.capture('inbox', {
        'entries': [item],
        'counts': {'new': 1},
      });
      final repo = DashboardRepository(db);
      await tester.pumpWidget(
        page(InboxWidget(repo: repo, openWriting: (_) {})),
      );
      await tester.tap(find.text('Входящие мысли · 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item['title']));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Заметка')).controller!.text,
        item['body'],
      );
      await tester.enterText(
        field('Заметка'),
        'Первая строка\nВторая строка\nМоя правка',
      );
      await tester.tap(find.text('В избранное'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Избранное'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item['title']));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Обработал · в архив'));
      await tester.pumpAndSettle();
      expect(repo.pending.length, 1);
      final command = object(repo.pending.single['body']);
      expect(command['action'], 'archive');
      expect(object(command['input'])['favorite'], true);
      expect(
        object(command['input'])['body'],
        'Первая строка\nВторая строка\nМоя правка',
      );
      expect(repo.entity('inbox:note', item)['status'], 'archived');
      expect(
        repo.cache('inbox')['entries'][0]['sourceText'],
        item['sourceText'],
      );
      await tester.tap(find.text('Архив'));
      await tester.pumpAndSettle();
      expect(find.text(item['title']), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
}
