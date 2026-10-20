import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/active_timer_conflict.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/focus_repository.dart';
import 'package:indicators_work/local_database.dart';

String work(FocusRepository repo, String title) {
  final id = uuid.v4();
  repo.nativeSave('workspace', 'saveWorkItem', {
    'id': id,
    'create': true,
    'title': title,
    'description': '  Первая\nВторая · 思考  ',
  }, 'work:$id');
  return 'work:$id';
}

void norm(
  FocusRepository repo,
  String ref,
  String title,
  int? count, {
  bool create = true,
  String? date,
  dynamic stamp,
}) {
  final day = date ?? today();
  repo.nativeSave(
    'pomodoroTarget',
    'save',
    {
      'date': day,
      'workRef': ref,
      'title': title,
      'target': count,
      if (create) 'create': true,
    },
    'pomodoro:$day:$ref',
    expectedUpdatedAt: stamp,
  );
}

void makeElapsed(FocusRepository repo, int seconds) {
  final timer = repo.cache('timer'), s = {...repo.active!};
  final at = repo.now - seconds * 1000;
  s['runningSince'] = at;
  s['startedAt'] = DateTime.fromMillisecondsSinceEpoch(
    at,
    isUtc: true,
  ).toIso8601String();
  repo.local.capture('timer', {
    ...timer,
    'active': s,
    'sessions': [
      ...rows(timer['sessions']).where((r) => r['id'] != s['id']),
      s,
    ],
  });
}

void main() {
  test('Fresh standalone archive creates two norms without a server, network or outbox', () async {
    var requests = 0;
    final repo = FocusRepository(
      LocalDatabase(':memory:'),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }),
    );
    addTearDown(repo.dispose);
    final one = work(repo, 'Чтение'), two = work(repo, 'Проект');
    norm(repo, one, 'Чтение', 1);
    norm(repo, two, 'Проект', 2);
    expect(repo.pomodoroTargetsForDate().map((n) => n['target']), [1, 2]);
    expect(repo.pending, isEmpty);
    expect(repo.local.drafts, isEmpty);
    expect(repo.local.get('serverId'), isNull);
    await repo.synchronize();
    repo.requestAutoSync();
    expect(requests, 0);
    expect(
      repo.entities('workItems', 'work').first['description'],
      '  Первая\nВторая · 思考  ',
    );
  });
  test('Completed pomodoro persists across restart, no confirmation queue or duplicate fact', () async {
    final directory = Directory.systemTemp.createTempSync('focus-norms-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = '${directory.path}/focus.sqlite';
    var repo = FocusRepository(LocalDatabase(file));
    final archive = repo.serverId;
    final one = work(repo, 'Чтение'), two = work(repo, 'Проект');
    norm(repo, one, 'Чтение', 1);
    norm(repo, two, 'Проект', 2);
    repo.setFocusPreferences({
      ...timerDefaults,
      'workMinutes': 1,
      'strategy': 'shared',
      'mode': 'pomodoro',
    });
    await repo.focusWork(ref: one, title: 'Чтение');
    makeElapsed(repo, 60);
    await repo.timerAction(
      'finish',
      observation: '  Применил идею\nСдвиг · 思考  ',
      workedSeconds: 60,
    );
    expect(repo.pomodoroTargetsForDate().map((n) => n['actualPomodoros']), [
      1,
      0,
    ]);
    expect(repo.pending, isEmpty);
    repo.dispose();
    repo = FocusRepository(LocalDatabase(file));
    addTearDown(repo.dispose);
    expect(repo.serverId, archive);
    expect(repo.pomodoroFacts.length, 1);
    expect(repo.pomodoroTargetsForDate().first['pendingPomodoros'], 0);
    expect(
      rows(repo.cache('timer')['sessions']).single['observation'],
      '  Применил идею\nСдвиг · 思考  ',
    );
    final export = await repo.exportLocal(directory.path);
    final data = jsonDecode(File(export).readAsStringSync());
    expect(data['format'], 'focus-norms-backup');
    expect(data['archiveId'], archive);
    expect(data['workspace']['workItems'].length, 2);
  });
  test(
    'Pause blocks another work and repeated Play resumes same session',
    () async {
      final repo = FocusRepository(LocalDatabase(':memory:'));
      addTearDown(repo.dispose);
      final one = work(repo, 'Первая'), two = work(repo, 'Вторая');
      await repo.focusWork(ref: one, title: 'Первая');
      final id = repo.active!['id'];
      await repo.timerAction('pause');
      await expectLater(
        repo.focusWork(ref: two, title: 'Вторая'),
        throwsA(isA<ActiveTimerConflict>()),
      );
      expect(repo.active!['status'], 'paused');
      await repo.focusWork(ref: one, title: 'Первая');
      expect(repo.active!['id'], id);
      expect(repo.active!['status'], 'running');
      expect(repo.pending, isEmpty);
    },
  );
  test(
    'Backup restores without network and keeps previous and raw source copies',
    () async {
      final directory = Directory.systemTemp.createTempSync('focus-restore-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final source = FocusRepository(LocalDatabase(':memory:'));
      addTearDown(source.dispose);
      final ref = work(source, '  Чтение · 思考  ');
      norm(source, ref, '  Личная норма  ', 2);
      await source.focusWork(ref: ref, title: 'Чтение');
      makeElapsed(source, 12);
      final path = await source.exportLocal(directory.path),
          raw = File(path).readAsStringSync();
      final destination = FocusRepository(LocalDatabase(':memory:'));
      addTearDown(destination.dispose);
      work(destination, 'Прежняя работа');
      final previous = await destination.restoreBackup(raw, directory.path);
      expect(File(previous).existsSync(), true);
      expect(
        jsonDecode(
          File(previous).readAsStringSync(),
        )['workspace']['workItems'].single['title'],
        'Прежняя работа',
      );
      expect(destination.serverId, source.serverId);
      expect(destination.active!['status'], 'paused');
      expect(
        elapsedMs(destination.active!, destination.now),
        closeTo(12000, 1000),
      );
      expect(
        destination.entities('workItems', 'work').single['title'],
        '  Чтение · 思考  ',
      );
      expect(destination.pomodoroTargetsForDate().single['target'], 2);
      expect(destination.pending, isEmpty);
      final original = directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('imported-backup'))
          .single;
      expect(original.readAsStringSync(), raw);
    },
  );
  test(
    'Bad backup and restore while working preserve current SQLite state',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'focus-bad-backup-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final repo = FocusRepository(LocalDatabase(':memory:'));
      addTearDown(repo.dispose);
      final ref = work(repo, 'Моя работа');
      norm(repo, ref, 'Моя норма', 1);
      final path = await repo.exportLocal(directory.path),
          data = jsonDecode(File(path).readAsStringSync());
      final before = jsonEncode(repo.cache('workspace'));
      data['dailyNorms']['pomodoroTargets'][0]['workRef'] = 'work:missing';
      await expectLater(
        repo.restoreBackup(jsonEncode(data), directory.path),
        throwsArgumentError,
      );
      expect(jsonEncode(repo.cache('workspace')), before);
      await repo.focusWork(ref: ref, title: 'Моя работа');
      final id = repo.active!['id'];
      await expectLater(
        repo.restoreBackup(File(path).readAsStringSync(), directory.path),
        throwsStateError,
      );
      expect(repo.active!['id'], id);
    },
  );
  test(
    'Norm removal and revisions preserve history and do not revive on next day',
    () {
      final repo = FocusRepository(LocalDatabase(':memory:'));
      addTearDown(repo.dispose);
      final ref = work(repo, 'Чтение');
      norm(repo, ref, 'Чтение', 1, date: '2026-10-20');
      expect(
        () => norm(repo, ref, 'Другое имя', 3, date: '2026-10-20'),
        throwsStateError,
      );
      norm(repo, ref, 'Чтение', null, create: false, date: '2026-10-21');
      expect(repo.pomodoroTargetsForDate('2026-10-20').length, 1);
      expect(repo.pomodoroTargetsForDate('2026-10-22'), isEmpty);
      expect(repo.pomodoroRows.length, 2);
    },
  );
  test('Minutes split at local midnight; cancelled work never adds time', () {
    final repo = FocusRepository(LocalDatabase(':memory:'));
    addTearDown(repo.dispose);
    final start = DateTime.parse('2026-10-20T18:59:30Z').millisecondsSinceEpoch;
    final s = newLocalSession(title: 'Переход дня', now: start);
    final finished = changeLocalSession(s, 'finish', start + 60000);
    final cancelled = changeLocalSession(
      newLocalSession(title: 'Отмена', now: start + 60000),
      'cancel',
      start + 120000,
    );
    repo.local.capture('timer', {
      'active': null,
      'sessions': [finished, cancelled],
    });
    expect(repo.workedMillisecondsByDay, {
      '2026-10-20': 30000,
      '2026-10-21': 30000,
    });
  });
}
