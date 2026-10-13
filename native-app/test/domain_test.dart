import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/reminders.dart';
import 'package:indicators_work/writing_screen.dart';

void main() {
  test('stopwatch stops accounting at 24 hours and clock rollback preserves the source', () {
    final start = DateTime.utc(2026, 10, 13).millisecondsSinceEpoch;
    final s = newLocalSession(
      title: 'Длительная работа',
      now: start,
      mode: 'stopwatch',
      settings: timerDefaults,
    );
    expect(elapsedMs(s, start + 48 * 3600000), 24 * 3600000);
    expect(() => changeLocalSession(s, 'pause', start - 1), throwsStateError);
    expect(s['status'], 'running');
  });
  test('pause, resume and pomodoro cap survive reconstruction and exclude the pause', () {
    final start = DateTime.utc(2026, 10, 13, 10).millisecondsSinceEpoch;
    var s = newLocalSession(
      title: 'Кейс · 问题',
      workRef: 'case:test',
      now: start,
    );
    s = changeLocalSession(s, 'pause', start + 5 * 60000);
    expect(elapsedMs(s, start + 60 * 60000), 5 * 60000);
    s = changeLocalSession(s, 'resume', start + 60 * 60000);
    expect(elapsedMs(s, start + 120 * 60000), 25 * 60000);
    s = changeLocalSession(
      s,
      'finish',
      start + 120 * 60000,
      observation: '  Хорошо · 模型  ',
    );
    expect(s['observation'], '  Хорошо · 模型  ');
    expect(s['completedPomodoros'], 1);
    expect(rows(s['intervals']).length, 2);
    expect(caption(s), 'Working on a problem: Кейс · 问题');
  });
  test('local completion and outbox commit atomically, retry waits for receipt and survives restart', () {
    final folder = Directory.systemTemp.createTempSync('iw-flutter-'),
        file = '${folder.path}/device.sqlite';
    var db = LocalDatabase(file);
    final start = DateTime.utc(2026, 10, 13, 10).millisecondsSinceEpoch;
    var s = newLocalSession(title: 'Работа', now: start);
    db.set('localActive', s);
    s = changeLocalSession(s, 'finish', start + 60000, observation: 'Успел');
    db.finishLocal(s, 'server-one');
    db.close();
    db = LocalDatabase(file);
    expect(db.get('localActive'), null);
    expect(db.queue.length, 1);
    expect(db.queue.single['server_id'], 'server-one');
    expect(
      object(object(db.queue.single['body'])['session'])['observation'],
      'Успел',
    );
    final id = db.queue.single['id'].toString();
    db.attempted(id);
    db.conflict(id, 'overlap');
    expect(db.queue.length, 1);
    db.retry(id);
    expect(db.queue.single['state'], 'queued');
    db.acknowledge(id);
    expect(db.queue, isEmpty);
    expect(rows(db.get('localHistory')).length, 1);
    db.close();
  });
  test(
    'hourly reminder is hidden until its next scheduled hour, then returns',
    () {
      final norm = {
        'workRef': 'work:one',
        'minutes': 60,
        'time': '09:00',
        'days': [1, 2, 3, 4, 5, 6, 7],
        'enabled': true,
      };
      final at = DateTime.parse('2026-10-13T09:20:00+05:00')
          .millisecondsSinceEpoch;
      expect(shouldShow(norm, at), true);
      final next = nextReminder(norm, at);
      expect(
        next,
        DateTime.parse('2026-10-13T10:00:00+05:00').millisecondsSinceEpoch,
      );
      expect(shouldShow(norm, at, hiddenUntil: next), false);
      expect(shouldShow(norm, next, hiddenUntil: next), true);
      expect(shouldShow(norm, next, confirmed: true), false);
      expect(shouldShow(norm, next, actualMinutes: 60), false);
    },
  );
  test('divider and H4 round trip through the native editor without changing server Delta', () {
    final source = {
      'ops': [
        {'insert': 'Заголовок'},
        {
          'insert': '\n',
          'attributes': {'header': 4},
        },
        {
          'insert': {'divider': true},
        },
        {'insert': '\nПосле линии\n'},
      ],
    };
    expect(editorDocument(editorDocument(source), toServer: true), source);
  });
  test('two unsent edits coalesce but an attempted edit cannot be silently replaced', () {
    final db = LocalDatabase(':memory:');
    db.set('serverId', 'server-one');
    final first = {
      'requestId': 'one',
      'module': 'workspace',
      'action': 'saveCase',
      'expectedUpdatedAt': null,
      'input': {'clientId': 'fixed-id', 'title': 'First'},
    };
    db.enqueue('case:fixed-id', '/api/native/command', first);
    db.enqueue('case:fixed-id', '/api/native/command', {
      'requestId': 'two',
      'module': 'workspace',
      'action': 'saveCase',
      'expectedUpdatedAt': 'newer',
      'input': {'id': 'fixed-id', 'title': 'Second'},
    });
    expect(db.queue.length, 1);
    final input = object(object(db.queue.single['body'])['input']);
    expect(input['clientId'], 'fixed-id');
    expect(input.containsKey('id'), false);
    expect(object(db.queue.single['body'])['expectedUpdatedAt'], null);
    db.attempted('two');
    expect(
      () => db.enqueue('case:fixed-id', '/api/native/command', first),
      throwsStateError,
    );
    db.close();
  });
}
