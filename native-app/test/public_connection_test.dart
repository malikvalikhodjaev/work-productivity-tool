import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/connection_bootstrap.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';

void main() {
  test(
    'authorization is scoped to origin; redirects are not followed',
    () async {
      final db = LocalDatabase(':memory:');
      final repo = DashboardRepository(
        db,
        client: MockClient((request) async {
          expect(request.followRedirects, false);
          expect(
            request.headers['Authorization'],
            request.url.host == 'owner.example'
                ? 'Basic ${base64Encode(utf8.encode('owner:local-test-key'))}'
                : null,
          );
          return http.Response(
            '{}',
            request.url.host == 'redirect.example' ? 302 : 200,
            headers: {'location': 'https://other.example'},
          );
        }),
      );
      addTearDown(repo.dispose);
      repo.setBase('https://owner.example');
      repo.setServerAccessKey('local-test-key');
      await repo.request('/api/timer');
      await expectLater(
        repo.request('https://other.example/api/timer'),
        throwsArgumentError,
      );
      repo.setBase('https://redirect.example');
      await expectLater(repo.request('/api/timer'), throwsA(isA<ApiFailure>()));
      expect(jsonEncode(db.export()), isNot(contains('local-test-key')));
      expect(
        db.export()['settings'].any((e) => e['key'] == 'serverAuth'),
        false,
      );
    },
  );
  test('bootstrap preserves archive, raw drafts and outbox; rejects mismatched archive', () async {
    final folder = await Directory.systemTemp.createTemp('iw-connection-test-');
    final db = LocalDatabase(':memory:');
    addTearDown(db.close);
    addTearDown(() => folder.delete(recursive: true));
    db.set('serverId', 'same-archive');
    db.keepDraft('note', {'text': '  raw\nparagraph  '});
    db.enqueue('note', '/api/writing', {
      'action': 'save',
      'text': '  raw\nparagraph  ',
    });
    final before = jsonEncode(db.drafts);
    final queueBefore = jsonEncode(db.queue);
    final file = File('${folder.path}/iw-connection.json');
    final data = {
      'version': 1,
      'serverId': 'other-archive',
      'origin': 'https://owner.example',
      'authorization': 'Basic b3duZXI6dGVzdA==',
    };
    await file.writeAsString(jsonEncode(data));
    await expectLater(
      applyConnectionBootstrap(db, file),
      throwsFormatException,
    );
    expect(await file.exists(), true);
    expect(db.get('baseUrl'), null);
    await file.writeAsString(jsonEncode({...data, 'serverId': 'same-archive'}));
    expect(await applyConnectionBootstrap(db, file), true);
    expect(await file.exists(), false);
    expect(db.get('serverId'), 'same-archive');
    expect(jsonEncode(db.drafts), before);
    expect(jsonEncode(db.queue), queueBefore);
  });
}
