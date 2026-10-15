import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'domain.dart';
import 'local_database.dart';
import 'pomodoro_plan.dart';

class ApiFailure implements Exception {
  final String message;
  final int status;
  ApiFailure(this.message, this.status);
  @override
  String toString() => message;
}

class DashboardRepository extends ChangeNotifier {
  final LocalDatabase local;
  final http.Client _http;
  Timer? _poll;
  bool syncing = false, online = false;
  String status = 'Локальное хранилище готово';
  DashboardRepository(this.local, {http.Client? client})
    : _http = client ?? http.Client();
  static const endpoints = {
    'dashboard': '/api/dashboard',
    'workspace': '/api/workspace',
    'portfolio': '/api/portfolio',
    'problems': '/api/daily-problems',
    'timer': '/api/timer',
    'writing': '/api/writing',
    'writingExport': '/api/writing/export',
    'entries': '/api/time-entries',
    'imports': '/api/imported-data',
    'hints': '/api/reflection-hints',
    'references': '/api/references',
    'ratings': '/api/indicator-ratings',
    'finance': '/api/finance',
    'dailyNorms': '/api/daily-norms',
    'inbox': '/api/inbox',
  };
  String get base =>
      (local.get('baseUrl') ?? 'http://localhost:8787').toString();
  void setTimerOnMinimize(bool enabled) {
    local.set('timerOnMinimize', enabled);
    notifyListeners();
  }

  String? get serverId => local.get('serverId') as String?;
  String get deviceId => local.get('deviceId') as String;
  Json cache(String key) => local.snapshot(key);
  List<Json> get pending => local.queue;
  Json? get localActive =>
      local.get('localActive') is Map ? object(local.get('localActive')) : null;
  Json? get active =>
      localActive ??
      (cache('timer')['active'] is Map
          ? object(cache('timer')['active'])
          : null);
  bool get isLocal => localActive != null;
  int get now =>
      DateTime.now().millisecondsSinceEpoch +
      (isLocal ? 0 : (local.get('serverOffset') as int? ?? 0));
  Json get settings => object(
    local.get('timerSettings') ?? cache('timer')['settings'] ?? timerDefaults,
  );
  void startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(synchronize()),
    );
    unawaited(synchronize());
  }

  void setBase(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['', '/'].contains(uri.path) ||
        !(uri.scheme == 'https' ||
            uri.scheme == 'http' &&
                ['localhost', '127.0.0.1', '::1'].contains(uri.host))) {
      throw ArgumentError(
        'Укажи HTTPS-адрес сервера либо http://localhost:8787 на этом ПК.',
      );
    }
    local.set('baseUrl', uri.origin);
    online = false;
    notifyListeners();
  }

  Future<Json> request(String route, {Json? body}) async {
    final uri = Uri.parse(base).resolve(route);
    final headers = {
      'Origin': Uri.parse(base).origin,
      'Content-Type': 'application/json',
    };
    final response =
        await (body == null
                ? _http.get(uri, headers: headers)
                : _http.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 10));
    Json result;
    try {
      result = object(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (_) {
      throw ApiFailure(
        'Сервер вернул неизвестный ответ (${response.statusCode}).',
        response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      throw ApiFailure(
        (result['error'] ?? 'Ошибка сервера ${response.statusCode}').toString(),
        response.statusCode,
      );
    }
    return result;
  }

  Future<void> synchronize() async {
    if (syncing) return;
    syncing = true;
    notifyListeners();
    try {
      final context = await request(
        '/api/offline/connect',
        body: {'deviceId': deviceId},
      );
      if (serverId != null && context['serverId'] != serverId) {
        throw ApiFailure(
          'Это другая установка сервера. Очередь и локальные записи сохранены; автоматическая отправка запрещена.',
          409,
        );
      }
      if (serverId == null) local.set('serverId', context['serverId']);
      local.capture('context', context);
      online = true;
      for (final queued in pending) {
        final item = local.queue.firstWhere((q) => q['id'] == queued['id']);
        if (item['state'] == 'conflict') break;
        if (item['server_id'] != serverId) {
          local.conflict(
            item['id'] as String,
            'Запись связана с другой установкой сервера.',
          );
          break;
        }
        local.attempted(item['id'] as String);
        try {
          final response = await request(
            item['route'] as String,
            body: object(item['body']),
          );
          local.atomic(() {
            if (item['route'] == '/api/offline/import' &&
                object(response['receipt'])['status'] == 'accepted') {
              final fact = pomodoroFact(
                object(object(item['body'])['session']),
              );
              if (fact != null) {
                final accepted = object(local.get('acceptedPomodoroFacts'));
                accepted[fact['sessionId'].toString()] = fact;
                local.set('acceptedPomodoroFacts', accepted);
              }
            }
            if (object(item['body'])['module'] == 'problem' &&
                response['problem'] is Map) {
              final preferred = object(item['body'])['caseClientId'];
              final linked = object(response['problem'])['caseRef'];
              if (preferred != null && linked is String) {
                local.remapRef('case:$preferred', linked);
                local.db.execute('DELETE FROM drafts WHERE entity=?', [
                  'case:$preferred',
                ]);
              }
            }
            for (final key in [
              'workspace',
              'portfolio',
              'dashboard',
              'dailyNorms',
              'inbox',
              'writing',
              'writingExport',
            ]) {
              if (response[key] is Map) {
                local.capture(key, object(response[key]));
              }
            }
            for (final article in rows(
              object(response['writingExport'])['entries'],
            )) {
              local.capture('writing:${article['id']}', article);
            }
            if (item['route'] == '/api/writing' && response['entry'] is Map) {
              local.capture(
                'writing:${response['entry']['id']}',
                object(response['entry']),
              );
            }
          });
          local.acknowledge(item['id'] as String);
        } on ApiFailure catch (e) {
          if (e.status >= 400 && e.status < 500) {
            local.conflict(item['id'] as String, e.message);
            break;
          }
          rethrow;
        }
      }
      final values = await Future.wait(
        endpoints.entries.map(
          (entry) async => MapEntry(entry.key, await request(entry.value)),
        ),
      );
      local.atomic(() {
        for (final entry in values) {
          local.capture(entry.key, entry.value);
        }
        for (final article in rows(
          local.snapshot('writingExport')['entries'],
        )) {
          local.capture('writing:${article['id']}', article);
        }
        final timer = local.snapshot('timer');
        if (timer['serverNow'] != null) {
          local.set(
            'serverOffset',
            DateTime.parse(timer['serverNow'].toString())
                    .millisecondsSinceEpoch -
                DateTime.now().millisecondsSinceEpoch,
          );
        }
      });
      status = pending.any((q) => q['state'] == 'conflict')
          ? 'Нужен разбор очереди'
          : 'Синхронизировано · ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
    } catch (e) {
      online = false;
      status = e.toString();
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  void nativeSave(
    String module,
    String action,
    Json input,
    String entity, {
    Json? draft,
    dynamic expectedUpdatedAt,
    dynamic expectedTarget,
  }) {
    if (serverId == null) {
      throw StateError('Сначала подключи приложение к своему серверу.');
    }
    final projected =
        draft ??
        {
          ...input,
          if (input['id'] == null && input['clientId'] != null)
            'id': input['clientId'],
        };
    local.enqueue(entity, '/api/native/command', {
      'requestId': uuid.v4(),
      'serverId': serverId,
      'deviceId': deviceId,
      'module': module,
      'action': action,
      'input': input,
      'expectedUpdatedAt': expectedUpdatedAt,
      if (module == 'target') 'expectedTarget': expectedTarget,
    }, draft: projected);
    status = 'Сохранено на устройстве · ожидает синхронизации';
    notifyListeners();
    unawaited(synchronize());
  }

  String saveProblem(String date, String text) {
    if (serverId == null) throw StateError('Сначала подключи свой сервер.');
    if (text.trim().isEmpty || text.length > 2000) {
      throw ArgumentError('Проблема: 1–2000 символов.');
    }
    final old =
        rows(cache('problems')['entries'])
            .where((p) => p['date'] == date)
            .firstOrNull ??
        <String, dynamic>{};
    final existing = local.draft('problem:$date');
    final ref = (existing?['caseRef'] ?? old['caseRef'] ?? 'case:${uuid.v4()}')
        .toString();
    final id = ref.substring(5);
    local.enqueue(
      'problem:$date',
      '/api/native/command',
      {
        'requestId': uuid.v4(),
        'serverId': serverId,
        'deviceId': deviceId,
        'module': 'problem',
        'action': 'save',
        'caseClientId': id,
        'input': {
          'date': date,
          'text': text,
          'expectedUpdatedAt': old['updatedAt'],
        },
      },
      draft: {'date': date, 'text': text, 'caseRef': ref},
    );
    if (!entities('cases', 'case').any((c) => c['id'] == id)) {
      local.keepDraft(ref, {
        'id': id,
        'title': text.length > 200 ? '${text.substring(0, 199)}…' : text,
        'context': text,
        'status': 'active',
        'pendingProblem': true,
      });
    }
    notifyListeners();
    unawaited(synchronize());
    return ref;
  }

  Json entity(String key, Json source) => local.draft(key) ?? source;
  List<Json> entities(String collection, String prefix) {
    final source = rows(
      cache(
        collection == 'alphas' ||
                collection == 'projects' ||
                collection == 'tasks'
            ? 'portfolio'
            : 'workspace',
      )[collection],
    );
    final items = {
      for (final row in source)
        '$prefix:${row['id']}': entity('$prefix:${row['id']}', row),
    };
    for (final draft in local.drafts.where(
      (d) => d['entity'].toString().startsWith('$prefix:'),
    )) {
      items[draft['entity'] as String] = object(draft['body']);
    }
    return items.values.toList();
  }

  List<Json> get dailyNorms {
    final result = {
      for (final n in rows(cache('dailyNorms')['norms']))
        n['workRef']: entity('norm:${n['workRef']}', n),
    };
    for (final draft in local.drafts.where(
      (d) => d['entity'].toString().startsWith('norm:'),
    )) {
      final n = object(draft['body']);
      result[n['workRef']] = n;
    }
    final date = today();
    final all = rows(cache('entries')['entries']);
    final from = DateTime.parse('${date}T00:00:00+05:00')
            .millisecondsSinceEpoch,
        to = from + 86400000;
    return result.values.where((n) => n['minutes'] != null).map((n) {
      final entries = all.where(
        (e) =>
            e['date'] == date &&
            e['workRef'] == n['workRef'] &&
            e['metricId'] != 'alphas',
      );
      final actual = entries.fold<double>(
        0,
        (s, e) =>
            s +
            (e['durationSeconds'] as num? ?? (e['amount'] as num) * 3600) / 60,
      );
      var pendingMinutes = 0.0;
      for (final item in pending.where(
        (q) => q['route'] == '/api/offline/import' && q['state'] != 'conflict',
      )) {
        final session = object(object(item['body'])['session']);
        if (session['workRef'] != n['workRef'] ||
            session['status'] != 'finished' ||
            all.any((e) => e['timerSessionId'] == session['id'])) {
          continue;
        }
        for (final interval in rows(session['intervals'])) {
          final start = (interval['start'] as int) > from
              ? interval['start'] as int
              : from;
          final end = (interval['end'] as int) < to
              ? interval['end'] as int
              : to;
          if (end > start) pendingMinutes += (end - start) / 60000;
        }
      }
      return {
        ...n,
        'title':
            rows(cache('workspace')['entities'])
                .where((e) => e['ref'] == n['workRef'])
                .firstOrNull?['title'] ??
            n['title'] ??
            n['workRef'],
        'actualMinutes': entries.isEmpty && pendingMinutes == 0
            ? null
            : actual + pendingMinutes,
        'pendingMinutes': pendingMinutes,
      };
    }).toList();
  }

  List<Json> get pomodoroRows {
    final result = <String, Json>{
      for (final n in rows(cache('dailyNorms')['pomodoroTargets']))
        '${n['date']}:${n['workRef']}': n,
    };
    for (final draft in local.drafts.where(
      (d) => d['entity'].toString().startsWith('pomodoro:'),
    )) {
      final n = object(draft['body']);
      result['${n['date']}:${n['workRef']}'] = n;
    }
    return result.values.toList();
  }

  List<Json> get pomodoroFacts {
    final facts = <String, Json>{
      for (final f in object(
        local.get('acceptedPomodoroFacts'),
      ).values.whereType<Map>())
        f['sessionId'].toString(): object(f),
      for (final f in rows(cache('dailyNorms')['pomodoroFacts']))
        f['sessionId'].toString(): f,
    };
    for (final session in rows(cache('timer')['sessions'])) {
      final fact = pomodoroFact(session);
      if (fact != null) facts[session['id'].toString()] = fact;
    }
    final confirmedIds = rows(cache('entries')['entries'])
        .map((e) => e['timerSessionId'])
        .toSet();
    for (final queued in pending.where(
      (q) => q['route'] == '/api/offline/import' && q['state'] != 'conflict',
    )) {
      final session = object(object(queued['body'])['session']);
      final fact = pomodoroFact(session);
      if (fact != null && !confirmedIds.contains(session['id'])) {
        facts.putIfAbsent(
          session['id'].toString(),
          () => {...fact, 'pending': true},
        );
      }
    }
    return facts.values.toList();
  }

  List<Json> pomodoroTargetsForDate([String? date]) {
    final day = date ?? today();
    return pomodoroRows
        .where((n) => n['date'] == day && n['target'] != null)
        .map((n) {
          final facts = pomodoroFacts
              .where((f) => f['date'] == day && f['workRef'] == n['workRef'])
              .toList();
          return {
            ...n,
            'actualPomodoros': facts.length,
            'pendingPomodoros': facts.where((f) => f['pending'] == true).length,
          };
        })
        .toList();
  }

  bool get hasPomodoroPlan => pomodoroTargetsForDate().isNotEmpty;

  List<Json> get dailyChecks {
    final result = {
      for (final check in rows(cache('dailyNorms')['checks']))
        '${check['date']}:${check['workRef']}': check,
    };
    for (final draft in local.drafts.where(
      (d) => d['entity'].toString().startsWith('dailycheck:'),
    )) {
      final check = object(draft['body']);
      result['${check['date']}:${check['workRef']}'] = check;
    }
    return result.values.toList();
  }

  Future<void> sharedAction(String action, Json input) async {
    if (isLocal) throw StateError('Сначала заверши таймер этого устройства.');
    if (!online) {
      throw StateError(
        'Для общего сеанса нужна связь с сервером. Для самостоятельного учёта выбери таймер устройства.',
      );
    }
    if (local.get('pendingTimer') != null) {
      throw StateError(
        'Предыдущее действие ещё ждёт ответа. Нажми «Проверить действие».',
      );
    }
    final command = {
      'action': action,
      'input': {
        ...input,
        'requestId': uuid.v4(),
        'expectedRevision': cache('timer')['revision'] ?? 0,
      },
    };
    local.set('pendingTimer', command);
    await checkPendingTimer();
  }

  Future<void> checkPendingTimer() async {
    final command = local.get('pendingTimer');
    if (command == null) return;
    try {
      final result = await request('/api/timer', body: object(command));
      local.atomic(() {
        local.capture('timer', result);
        local.remove('pendingTimer');
      });
      notifyListeners();
    } on ApiFailure catch (e) {
      if (e.status == 409) {
        local.set('timerConflict', e.message);
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> abandonTimerCommand() async {
    if (local.get('pendingTimer') == null) return;
    final result = await request('/api/timer');
    local.atomic(() {
      local.capture('timer', result);
      local.remove('pendingTimer');
      local.remove('timerConflict');
    });
    notifyListeners();
  }

  Future<void> resolveConflict(Json item, {required bool apply}) async {
    if (!apply) {
      local.resolve(item['id'].toString());
      notifyListeners();
      unawaited(synchronize());
      return;
    }
    final body = object(item['body']);
    final input = object(body['input']);
    Json? current;
    if (item['route'] == '/api/writing') {
      current = cache('writing:${body['id']}');
      body['expectedRevision'] = current['revision'] ?? 0;
    } else if (item['route'] == '/api/native/command') {
      switch (body['module']) {
        case 'workspace':
          final collections = {
            'saveCase': 'cases',
            'saveGoal': 'goals',
            'saveSystem': 'systems',
            'saveWorkItem': 'workItems',
          };
          final collection = collections[body['action']];
          if (collection != null && input['id'] != null) {
            current = rows(cache('workspace')[collection])
                .where((r) => r['id'] == input['id'])
                .firstOrNull;
          }
          if (body['action'] == 'saveWorkNote') {
            current =
                rows(cache('workspace')['workNotes'])
                    .where((r) => r['workRef'] == input['workRef'])
                    .firstOrNull ??
                <String, dynamic>{};
          }
          if (current == null) {
            throw StateError(
              'Сначала сохрани правку локально, затем открой карточку и уточни её. Автоматически заменять новый объект нельзя.',
            );
          }
          if (['saveWorkItem', 'saveWorkNote'].contains(body['action'])) {
            input['expectedRevision'] = current['revision'] ?? 0;
            input['requestId'] = uuid.v4();
          } else {
            body['expectedUpdatedAt'] = current['updatedAt'];
          }
        case 'portfolio':
          final collection = {
            'updateProject': 'projects',
            'updateAlpha': 'alphas',
            'setTaskDone': 'tasks',
          }[body['action']];
          if (collection == null) {
            throw StateError('Для нового объекта открой и уточни карточку.');
          }
          current = rows(cache('portfolio')[collection])
              .where((r) => r['id'] == input['id'])
              .firstOrNull;
          if (current == null) {
            throw StateError('Объект не найден; исходник сохранён.');
          }
          body['expectedUpdatedAt'] = current['updatedAt'];
          input['expectedRevision'] = current['revision'] ?? 0;
        case 'problem':
          current = rows(cache('problems')['entries'])
              .where((r) => r['date'] == input['date'])
              .firstOrNull;
          input['expectedUpdatedAt'] = current?['updatedAt'];
        case 'pomodoroTarget':
          current = rows(cache('dailyNorms')['pomodoroTargets'])
              .where(
                (r) =>
                    r['workRef'] == input['workRef'] &&
                    r['date'] == input['date'],
              )
              .firstOrNull;
          body['expectedUpdatedAt'] = current?['updatedAt'];
        case 'inbox':
          current = rows(cache('inbox')['entries'])
              .where((r) => r['id'] == input['id'])
              .firstOrNull;
          if (current == null) {
            throw StateError('Входящая мысль не найдена. Исходник сохранён.');
          }
          body['expectedUpdatedAt'] = current['updatedAt'];
        case 'dailyNorm':
          current = rows(cache('dailyNorms')['norms'])
              .where((r) => r['workRef'] == input['workRef'])
              .firstOrNull;
          body['expectedUpdatedAt'] = current?['updatedAt'];
        case 'dailyCheck':
          current = rows(cache('dailyNorms')['checks'])
              .where(
                (r) =>
                    r['date'] == input['date'] &&
                    r['workRef'] == input['workRef'],
              )
              .firstOrNull;
          body['expectedUpdatedAt'] = current?['updatedAt'];
        case 'target':
          current = rows(cache('dashboard')['metrics'])
              .where((r) => r['id'] == input['metricId'])
              .firstOrNull;
          if (input['week'] != cache('dashboard')['week']) {
            throw StateError('Открой норматив нужной недели заново.');
          }
          body['expectedTarget'] = current?['target'];
        default:
          throw StateError(
            'Сохрани исходник локально и уточни запись в её разделе.',
          );
      }
      body['input'] = input;
    } else {
      throw StateError(
        'Сеанс времени можно повторить или явно исключить из учёта.',
      );
    }
    body['requestId'] = uuid.v4();
    local.resolve(item['id'].toString(), replacement: body);
    notifyListeners();
    unawaited(synchronize());
  }

  void startLocal(Json input, {bool independentConfirmed = false}) {
    if (localActive != null) {
      throw StateError('На устройстве уже есть активный сеанс.');
    }
    if (cache('timer')['active'] != null && !independentConfirmed) {
      throw StateError(
        'На сервере был активный сеанс. Подтверди независимый учёт; пересечения будут проверены при отправке.',
      );
    }
    if (serverId == null) {
      throw StateError('Для связанного учёта сначала подключи сервер.');
    }
    final session = newLocalSession(
      title: input['title'].toString(),
      workRef: input['workRef'] as String?,
      metricId: input['metricId'] as String?,
      allocation: (input['allocation'] ?? 'unclassified').toString(),
      workType: (input['workType'] ?? '').toString(),
      mode: (input['mode'] ?? 'pomodoro').toString(),
      phase: (input['phase'] ?? 'work').toString(),
      settings: settings,
      now: DateTime.now().millisecondsSinceEpoch,
    );
    local.set('localActive', session);
    notifyListeners();
  }

  Future<void> timerAction(
    String action, {
    String observation = '',
    int? workedSeconds,
  }) async {
    final s = active;
    if (s == null) return;
    if (isLocal) {
      final changed = changeLocalSession(
        s,
        action,
        now,
        observation: observation,
        workedSeconds: workedSeconds,
      );
      if (['finish', 'cancel'].contains(action)) {
        local.finishLocal(changed, serverId);
        unawaited(synchronize());
      } else {
        local.set('localActive', changed);
      }
      notifyListeners();
    } else {
      await sharedAction(action, {
        'sessionId': s['id'],
        if (action == 'finish') 'observation': observation,
        'workedSeconds': ?workedSeconds,
      });
    }
  }

  void saveWriting(Json article) {
    final archive = cache('writing')['instanceId'];
    if (archive == null) throw StateError('Сначала загрузи архив с сервера.');
    final original = cache('writing:${article['id']}');
    local.enqueue('writing:${article['id']}', '/api/writing', {
      'action': 'save',
      'requestId': uuid.v4(),
      'instanceId': archive,
      'id': article['id'],
      'expectedRevision': original['revision'] ?? 0,
      'title': article['title'],
      'date': article['date'],
      'status': article['status'],
      'document': article['document'],
    }, draft: article);
    notifyListeners();
    unawaited(synchronize());
  }

  Future<String> exportLocal(String folder) async {
    final destination = Platform.isAndroid ? '$folder/exports' : folder;
    final file = File(
      '$destination/iw-device-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(local.export()),
      flush: true,
    );
    return file.path;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _http.close();
    local.close();
    super.dispose();
  }
}
