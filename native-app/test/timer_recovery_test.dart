import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:indicators_work/domain.dart';
import 'package:indicators_work/local_database.dart';
import 'package:indicators_work/repository.dart';

http.Response response(Json body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

LocalDatabase database() {
  final db = LocalDatabase(':memory:');
  db.set('serverId', 'owner-server');
  db.capture('timer', {
    'revision': 1,
    'settings': timerDefaults,
    'active': newLocalSession(
      title: 'Моя работа',
      workRef: 'work:one',
      now: DateTime.now().millisecondsSinceEpoch - 120000,
    ),
  });
  return db;
}

Json command(LocalDatabase db, String action, {String? observation}) => {
  'action': action,
  'input': {
    'sessionId': object(db.snapshot('timer')['active'])['id'],
    'requestId': uuid.v4(),
    'expectedRevision': 0,
    'observation': ?observation,
  },
};

void main() {
  test('one pause click recovers a concurrent revision change and pauses only the selected session', () async {
    final db = database();
    var state = {...db.snapshot('timer'), 'revision': 12};
    final posts = <Json>[];
    final repo = DashboardRepository(
      db,
      client: MockClient((r) async {
        if (r.url.path == '/api/offline/connect') {
          return response({'serverId': 'owner-server'});
        }
        if (r.method == 'GET') return response(state);
        final body = object(jsonDecode(r.body));
        posts.add(body);
        if (posts.length == 1) {
          return response({'error': 'Изменена версия'}, 409);
        }
        expect(object(body['input'])['expectedRevision'], 12);
        expect(
          object(body['input'])['sessionId'],
          object(state['active'])['id'],
        );
        state = {
          ...state,
          'revision': 13,
          'active': changeLocalSession(
            object(state['active']),
            'pause',
            DateTime.now().millisecondsSinceEpoch,
          ),
        };
        return response(state);
      }),
    )..online = true;
    addTearDown(repo.dispose);
    await repo.timerAction('pause');
    expect(posts, hasLength(2));
    expect(
      object(posts[0]['input'])['requestId'],
      isNot(object(posts[1]['input'])['requestId']),
    );
    expect(repo.active?['status'], 'paused');
    expect(repo.timerPending, false);
  });
  test('lost pause reply replays identical command, then resume keeps the same session', () async {
    final db = database();
    var state = db.snapshot('timer');
    final sessionId = object(state['active'])['id'];
    final seen = <String, String>{};
    final posts = <Json>[];
    var loseReply = true;
    final repo = DashboardRepository(
      db,
      client: MockClient((r) async {
        if (r.url.path == '/api/offline/connect') {
          return response({'serverId': 'owner-server'});
        }
        final body = object(jsonDecode(r.body));
        posts.add(body);
        final input = object(body['input']);
        final id = input['requestId'].toString();
        if (seen.containsKey(id)) {
          expect(jsonEncode(body), seen[id]);
        } else {
          expect(input['expectedRevision'], state['revision']);
          seen[id] = jsonEncode(body);
          state = {
            ...state,
            'revision': (state['revision'] as int) + 1,
            'active': changeLocalSession(
              object(state['active']),
              body['action'].toString(),
              DateTime.now().millisecondsSinceEpoch,
            ),
          };
        }
        if (loseReply) {
          loseReply = false;
          throw http.ClientException('Reply lost after commit');
        }
        return response(state);
      }),
    )..online = true;
    addTearDown(repo.dispose);
    await expectLater(
      repo.timerAction('pause'),
      throwsA(isA<http.ClientException>()),
    );
    expect(repo.timerPending, true);
    await repo.timerAction('pause');
    expect(posts, hasLength(2));
    expect(posts[0], posts[1]);
    expect(repo.active?['status'], 'paused');
    final paused = elapsedMs(repo.active!, repo.now);
    expect(elapsedMs(repo.active!, repo.now + 600000), paused);
    await repo.timerAction('resume');
    expect(repo.active?['id'], sessionId);
    expect(repo.active?['status'], 'running');
    expect(seen, hasLength(2));
    expect(repo.timerPending, false);
  });

  test('stale pending action is archived; this pause uses fresh revision and new ID', () async {
    final db = database();
    final previous = command(db, 'extend');
    db.set('pendingTimer', previous);
    final state = {...db.snapshot('timer'), 'revision': 9};
    final posts = <Json>[];
    final repo = DashboardRepository(
      db,
      client: MockClient((r) async {
        if (r.url.path == '/api/offline/connect') {
          return response({'serverId': 'owner-server'});
        }
        if (r.method == 'GET') return response(state);
        final body = object(jsonDecode(r.body));
        posts.add(body);
        if (posts.length == 1) {
          return response({'error': 'Таймер изменён на ПК'}, 409);
        }
        expect(body['action'], 'pause');
        expect(object(body['input'])['expectedRevision'], 9);
        expect(
          object(body['input'])['requestId'],
          isNot(object(previous['input'])['requestId']),
        );
        return response({
          ...state,
          'revision': 10,
          'active': changeLocalSession(
            object(state['active']),
            'pause',
            DateTime.now().millisecondsSinceEpoch,
          ),
        });
      }),
    )..online = true;
    addTearDown(repo.dispose);
    await repo.timerAction('pause');
    expect(repo.active?['status'], 'paused');
    expect(repo.timerPending, false);
    expect(
      object(db.get('timerCommandHistory')).values.single['command'],
      previous,
    );
    expect(posts, hasLength(2));
  });

  test(
    'refresh never transfers an old pause to a different active session',
    () async {
      final db = database();
      db.set('pendingTimer', command(db, 'pause'));
      final other = newLocalSession(
        title: 'Другая',
        workRef: 'work:two',
        now: DateTime.now().millisecondsSinceEpoch,
      );
      var posts = 0;
      final repo = DashboardRepository(
        db,
        client: MockClient((r) async {
          if (r.url.path == '/api/offline/connect') {
            return response({'serverId': 'owner-server'});
          }
          if (r.method == 'GET') {
            return response({'revision': 4, 'active': other});
          }
          posts++;
          return response({'error': 'Сеанс завершён'}, 409);
        }),
      )..online = true;
      addTearDown(repo.dispose);
      await expectLater(repo.timerAction('pause'), throwsStateError);
      expect(posts, 1);
      expect(repo.active, other);
      expect(repo.timerPending, false);
    },
  );

  test('automatic synchronization reconciles pending rejection and retains observation verbatim', () async {
    final db = database();
    final previous = command(
      db,
      'finish',
      observation: '  Моё наблюдение · 思考  ',
    );
    db.set('pendingTimer', previous);
    final state = {...db.snapshot('timer'), 'revision': 5};
    var posts = 0;
    final repo = DashboardRepository(
      db,
      client: MockClient((r) async {
        if (r.url.path == '/api/offline/connect') {
          return response({'serverId': 'owner-server'});
        }
        if (r.method == 'POST') {
          posts++;
          return response({'error': 'Факт требует уточнения'}, 400);
        }
        return response(r.url.path == '/api/timer' ? state : {});
      }),
    );
    addTearDown(repo.dispose);
    await repo.synchronize();
    expect(repo.online, true);
    expect(posts, 1);
    expect(repo.timerPending, false);
    expect(repo.active?['status'], 'running');
    expect(
      object(db.get('timerCommandHistory')).values.single['command'],
      previous,
    );
  });

  test(
    'concurrent retries send one command; network loss retains the command',
    () async {
      final db = database();
      final original = command(db, 'pause');
      db.set('pendingTimer', original);
      final gate = Completer<void>();
      var posts = 0;
      final repo = DashboardRepository(
        db,
        client: MockClient((r) async {
          if (r.url.path == '/api/offline/connect') {
            return response({'serverId': 'owner-server'});
          }
          posts++;
          await gate.future;
          throw http.ClientException('No connection');
        }),
      )..online = true;
      addTearDown(repo.dispose);
      final first = repo.checkPendingTimer();
      final second = repo.checkPendingTimer();
      expect(identical(first, second), true);
      final failures = [
        expectLater(first, throwsA(isA<http.ClientException>())),
        expectLater(second, throwsA(isA<http.ClientException>())),
      ];
      gate.complete();
      await Future.wait(failures);
      expect(posts, 1);
      expect(db.get('pendingTimer'), original);
      expect(repo.timerBusy, false);
      expect(repo.localActive, isNull);
    },
  );

  test(
    'a different installation cannot receive pending timer commands',
    () async {
      final db = database();
      final original = command(db, 'pause');
      db.set('pendingTimer', original);
      var timerPosts = 0;
      final repo = DashboardRepository(
        db,
        client: MockClient((r) async {
          if (r.url.path == '/api/offline/connect') {
            return response({'serverId': 'different-server'});
          }
          timerPosts++;
          return response({});
        }),
      )..online = true;
      addTearDown(repo.dispose);
      await expectLater(repo.timerAction('pause'), throwsA(isA<ApiFailure>()));
      expect(timerPosts, 0);
      expect(db.get('pendingTimer'), original);
    },
  );
}
