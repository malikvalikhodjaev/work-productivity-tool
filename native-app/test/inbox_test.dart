import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/inbox_widget.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';

final item = <String, dynamic>{
  'id': 'entry',
  'title': 'Мысль на ходу',
  'kind': 'text',
  'sourceText': 'Что можно упростить?',
  'transcript': '',
  'notes': '',
  'status': 'new',
  'writingId': null,
  'updatedAt': '2026-10-15T00:00:00Z',
};
Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> testInbox(WidgetTester tester, DashboardRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: InboxWidget(repo: repo, openWriting: (_) {}),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Входящие мысли · 1'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Мысль на ходу'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Offline inbox conversion keeps my review and its original server version',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = LocalDatabase(':memory:');
      db.set('serverId', 'owner');
      db.capture('inbox', {
        'entries': [item],
        'counts': {'new': 1},
      });
      final repo = DashboardRepository(
        db,
        client: MockClient((_) async => http.Response('Unavailable', 503)),
      );
      await testInbox(tester, repo);
      await tester.enterText(field('Тема мысли'), 'Размышления · 中文');
      await tester.enterText(
        field('Мои мысли при разборе'),
        'Первый шаг\nВторой шаг',
      );
      await tester.tap(find.text('Создать черновик'));
      await tester.pumpAndSettle();
      expect(repo.pending, hasLength(1));
      final command = object(repo.pending.single['body']);
      expect(command['module'], 'inbox');
      expect(command['action'], 'convert');
      expect(command['expectedUpdatedAt'], item['updatedAt']);
      expect(object(command['input'])['notes'], 'Первый шаг\nВторой шаг');
      expect(db.draft('inbox:entry')?['title'], 'Размышления · 中文');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
  test('Acknowledged conversion updates inbox and writing cache and removes only its queue', () async {
    final db = LocalDatabase(':memory:');
    db.set('serverId', 'owner');
    db.capture('inbox', {
      'entries': [item],
      'counts': {'new': 1},
    });
    final article = {
      'id': 'article',
      'title': 'Эссе',
      'status': 'draft',
      'date': '2026-10-15',
      'revision': 1,
      'document': {
        'ops': [
          {'insert': 'Моя мысль\n'},
        ],
      },
    };
    final inbox = {
      'entries': [
        {...item, 'writingId': 'article', 'status': 'reviewed'},
      ],
      'counts': {'new': 0, 'reviewed': 1},
    };
    final repo = DashboardRepository(
      db,
      client: MockClient((request) async {
        final route = request.url.path;
        final result = route == '/api/offline/connect'
            ? {'serverId': 'owner'}
            : route == '/api/native/command'
            ? {
                'inbox': inbox,
                'writingExport': {
                  'entries': [article],
                },
                'writing': {
                  'entries': [article],
                },
              }
            : route == '/api/inbox'
            ? inbox
            : route == '/api/writing/export'
            ? {
                'entries': [article],
              }
            : <String, dynamic>{};
        return http.Response(jsonEncode(result), 200,headers:{'content-type':'application/json; charset=utf-8'});
      }),
    );
    repo.nativeSave(
      'inbox',
      'convert',
      {'id': 'entry'},
      'inbox:entry',
      expectedUpdatedAt: item['updatedAt'],
    );
    while (repo.syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(repo.pending, isEmpty);
    expect(repo.cache('writing:article')['title'], 'Эссе');
    expect(rows(repo.cache('inbox')['entries']).single['status'], 'reviewed');
    expect(db.draft('inbox:entry'), isNull);
    repo.dispose();
  });
}
