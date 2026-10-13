import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/main.dart';
import 'package:indicators_work/repository.dart';

void main() {
  setUp(() {
    final report = FlutterError.onError!;
    FlutterError.onError = (details) {
      debugPrint(details.toString());
      report(details);
    };
    addTearDown(() => FlutterError.onError = report);
  });
  testWidgets(
    'all five sections open on desktop and a typed divider can be undone; essay survives navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = LocalDatabase(':memory:');
      db.set('serverId', 'owner-server');
      final repo = DashboardRepository(
        db,
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      await tester.pumpWidget(
        DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
      );
      for (final title in [
        'Проекты',
        'Работа',
        'Данные',
        'Показатели',
        'Письмо',
      ]) {
        await tester.tap(find.widgetWithText(FilledButton, title).first);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: title);
      }
      await tester.tap(find.text('Новая запись'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField).first, 'Моя мысль · 思考');
      final editor = tester.widget<q.QuillEditor>(find.byType(q.QuillEditor));
      final controller = editor.controller;
      for (var i = 0; i < 3; i++) {
        controller.replaceText(
          i,
          0,
          '-',
          TextSelection.collapsed(offset: i + 1),
        );
        await tester.pump();
      }
      expect(
        controller.document.toDelta().toJson().any(
          (op) => op['insert'] is Map && op['insert']['divider'] != null,
        ),
        true,
      );
      controller.undo();
      await tester.pump();
      expect(controller.document.toPlainText().contains('---'), true);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.widgetWithText(FilledButton, 'Работа').first);
      await tester.pump();
      final saved = db.drafts
          .where((d) => d['entity'].toString().startsWith('composer:'))
          .single;
      expect(object(saved['body'])['title'], 'Моя мысль · 思考');
      expect(
        jsonEncode(object(saved['body'])['document']).contains('---'),
        true,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  testWidgets(
    'mobile navigation keeps all five sections available without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DashboardRepository(LocalDatabase(':memory:'));
      await tester.pumpWidget(
        DashboardApp(repo: repo, folder: '.', backgroundEnabled: false),
      );
      for (final label in [
        'Проекты',
        'Работа',
        'Письмо',
        'Данные',
        'Показатели',
      ]) {
        await tester.tap(find.widgetWithText(NavigationDestination, label));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: label);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  test('lost response preserves immutable command and retry acknowledges the same id after restart', () async {
    final directory = Directory.systemTemp.createTempSync('iw-retry-test-');
    final file = '${directory.path}/device.sqlite';
    var db = LocalDatabase(file);
    db.set('serverId', 'owner-server');
    final id = uuid.v4();
    final command = {
      'requestId': id,
      'serverId': 'owner-server',
      'deviceId': db.get('deviceId'),
      'module': 'workspace',
      'action': 'saveCase',
      'input': {'clientId': uuid.v4(), 'title': 'Причина · 原因'},
    };
    db.enqueue('case:new', '/api/native/command', command);
    final received = <String>[];
    var lost = true;
    http.Client client() => MockClient((request) async {
      if (request.url.path == '/api/offline/connect') {
        return http.Response('{"serverId":"owner-server"}', 200);
      }
      if (request.url.path == '/api/native/command') {
        received.add(request.body);
        if (lost) {
          lost = false;
          throw http.ClientException('response lost');
        }
      }
      return http.Response('{}', 200);
    });
    var repo = DashboardRepository(db, client: client());
    await repo.synchronize();
    expect(db.queue.single['attempted'], 1);
    expect(db.queue.single['id'], id);
    repo.dispose();
    db = LocalDatabase(file);
    repo = DashboardRepository(db, client: client());
    await repo.synchronize();
    expect(db.queue, isEmpty);
    expect(received, hasLength(2));
    expect(received[0], received[1]);
    repo.dispose();
    directory.deleteSync(recursive: true);
  });

  test('another server never receives the saved queue', () async {
    final db = LocalDatabase(':memory:');
    db.set('serverId', 'first-server');
    db.enqueue('case:private', '/api/native/command', {
      'requestId': uuid.v4(),
      'serverId': 'first-server',
    });
    var writes = 0;
    final repo = DashboardRepository(
      db,
      client: MockClient((request) async {
        if (request.url.path == '/api/offline/connect') {
          return http.Response('{"serverId":"another-server"}', 200);
        }
        writes++;
        return http.Response('{}', 200);
      }),
    );
    await repo.synchronize();
    expect(writes, 0);
    expect(db.queue, hasLength(1));
    expect(repo.online, false);
    repo.dispose();
  });
}
