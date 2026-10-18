import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'domain.dart';
import 'local_database.dart';
import 'pomodoro_plan.dart';
import 'durable_timer.dart';
import 'grid_definitions.dart';

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
  bool focusStarting = false;
  bool _sharedActionInFlight = false;
  Future<void>? _timerCheck;
  bool get timerBusy =>
      _sharedActionInFlight || (!durableTimer && _timerCheck != null);
  bool get timerPending =>
      local.get('pendingTimer') != null ||
      pending.any((q) => q['route'] == '/api/timer');
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

  void setAndroidOverlayEnabled(bool enabled) {
    local.set('androidOverlayEnabled', enabled);
    notifyListeners();
  }

  String? get serverId => local.get('serverId') as String?;
  String get deviceId => local.get('deviceId') as String;
  Json cache(String key) =>
      key == 'timer' && local.get('optimisticTimer') is Map
      ? object(local.get('optimisticTimer'))
      : local.snapshot(key);
  bool get durableTimer =>
      local.get('durableTimerEnabled') == true ||
      cache('timer')['offlineCommands'] == true;
  bool get automaticSync => local.get('automaticSync') != false;
  void setAutomaticSync(bool enabled) {
    local.set('automaticSync', enabled);
    notifyListeners();
    if (enabled) requestAutoSync();
  }

  void requestAutoSync() {
    if (automaticSync) unawaited(synchronize());
  }

  Json get todayProblem {
    final day = today();
    final saved = rows(cache('problems')['entries'])
        .where((entry) => entry['date'] == day)
        .firstOrNull;
    return entity('problem:$day', saved ?? <String, dynamic>{});
  }

  bool get todayProblemLoaded =>
      cache('problems').isNotEmpty || local.draft('problem:${today()}') != null;
  String get todayProblemText {
    if (!todayProblemLoaded) return 'No Data · проблема дня ещё не загружена';
    final text = (todayProblem['text'] ?? '').toString();
    return text.trim().isEmpty
        ? 'Главная проблема на сегодня не записана'
        : text;
  }

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
  String get timerStrategy =>
      (local.get('timerStrategy') ?? 'shared').toString();
  String get timerMode => (local.get('timerMode') ?? 'pomodoro').toString();

  void setFocusPreferences(Json input) {
    final nextSettings = {
      for (final key in timerDefaults.keys) key: input[key],
    };
    validateSettings(nextSettings);
    if (!['shared', 'local'].contains(input['strategy']) ||
        !['pomodoro', 'stopwatch'].contains(input['mode'])) {
      throw ArgumentError('Выбери режим и источник учёта таймера.');
    }
    local.atomic(() {
      local.set('timerSettings', nextSettings);
      local.set('timerStrategy', input['strategy']);
      local.set('timerMode', input['mode']);
    });
    notifyListeners();
  }

  Future<void> focusWork({
    required String ref,
    required String title,
    Json? item,
  }) async {
    if (focusStarting) return;
    focusStarting = true;
    notifyListeners();
    try {
      if (!durableTimer && !isLocal && timerPending && online) {
        await _recoverTimerCommand();
      }
      final s = active;
      if (s != null) {
        if (s['workRef'] != ref) {
          throw StateError(
            'Сейчас в фокусе другая работа. Сначала заверши её.',
          );
        }
        if (s['status'] == 'paused') await timerAction('resume');
        return;
      }
      final known = rows(cache('workspace')['entities'])
          .where((e) => e['ref'] == ref)
          .firstOrNull;
      final source = item ?? local.draft(ref) ?? known ?? <String, dynamic>{};
      if (title.trim().isEmpty) throw ArgumentError('Сначала назови работу.');
      if (!durableTimer &&
          timerStrategy == 'shared' &&
          local.draft(ref) != null &&
          known == null) {
        throw StateError(
          'Новая карточка ещё не отправлена на сервер. Синхронизируй её или выбери таймер устройства в настройках.',
        );
      }
      final input = {
        'title': title,
        'workRef': ref,
        'metricId': source['metricId'],
        'allocation': source['metricId'] != null
            ? 'assigned'
            : source['allocation'] ?? 'unclassified',
        'workType': source['workType'] ?? '',
        'mode': timerMode,
        'settings': settings,
      };
      if (timerStrategy == 'local') {
        startLocal(input);
      } else {
        await sharedAction('start', input);
      }
    } finally {
      focusStarting = false;
      notifyListeners();
    }
  }

  void startPolling() {
    local.set('durableTimerEnabled', true);
    _poll?.cancel();
    _poll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => requestAutoSync(),
    );
    requestAutoSync();
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
    final syncBase = base;
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
      if (local.get('pendingTimer') != null) await _recoverTimerCommand();
      for (final queued in pending) {
        if (base != syncBase) {
          throw StateError('Адрес изменён. Очередь сохранена для проверки.');
        }
        final item = local.queue.firstWhere((q) => q['id'] == queued['id']);
        if (item['state'] == 'conflict') break;
        if (item['server_id'] != serverId) {
          local.conflict(
            item['id'] as String,
            'Запись связана с другой установкой сервера.',
          );
          break;
        }
        if (item['route'] == '/api/timer' &&
            context['offlineCommands'] != true) {
          throw StateError(
            'Обнови сервер до версии 1.16.0. Записанное время осталось на устройстве.',
          );
        }
        local.attempted(item['id'] as String);
        try {
          final response = await request(
            item['route'] as String,
            body: object(item['body']),
          );
          if (base != syncBase) {
            throw StateError(
              'Адрес изменён. Подтверждение сохранения будет проверено при следующей связи.',
            );
          }
          local.atomic(() {
            if (item['route'] == '/api/timer') {
              _captureTimer(response);
              final receipts = object(local.get('timerCommandReceipts'));
              receipts[item['id'].toString()] = {
                'command': item['body'],
                'serverId': serverId,
                'acknowledgedAt': DateTime.now().toUtc().toIso8601String(),
                'revision': response['revision'],
              };
              local.set('timerCommandReceipts', receipts);
              if (object(item['body'])['action'] == 'finish') {
                final id = object(object(item['body'])['input'])['sessionId'];
                final session = rows(cache('timer')['sessions'])
                    .where((s) => s['id'] == id)
                    .firstOrNull;
                final fact = session == null ? null : pomodoroFact(session);
                if (fact != null) {
                  final accepted = object(local.get('acceptedPomodoroFacts'));
                  accepted[id.toString()] = fact;
                  local.set('acceptedPomodoroFacts', accepted);
                }
              }
            }
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
          _clearTimerProjectionIfAcknowledged();
        } on ApiFailure catch (e) {
          if (e.status >= 400 && e.status < 500) {
            local.conflict(item['id'] as String, e.message);
            if (item['route'] == '/api/timer') {
              local.set('timerChainConflict', true);
            }
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
      if (base != syncBase) {
        throw StateError('Адрес изменён. Локальные данные сохранены.');
      }
      local.atomic(() {
        for (final entry in values) {
          if (entry.key == 'timer') {
            _captureTimer(entry.value);
          } else {
            local.capture(entry.key, entry.value);
          }
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
          : pending.isNotEmpty
          ? 'Сохранено на устройстве · ожидает отправки: ${pending.length}'
          : 'Синхронизировано · ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
      local.set('lastSyncAt', DateTime.now().toUtc().toIso8601String());
      local.remove('lastSyncError');
    } catch (e) {
      online = false;
      local.set('lastSyncError', e.toString());
      status = 'Нет связи с сервером · изменения сохранены на устройстве';
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
    if (module == 'pomodoroTarget') {
      input = {...input, 'repeat': input['repeat'] ?? 'daily'};
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
    requestAutoSync();
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
    requestAutoSync();
    return ref;
  }

  Json entity(String key, Json source) => local.draft(key) ?? source;

  /// Cell commands have their own identity and retain the exact before/value pair.
  void gridCommand(String action, Json input) {
    if (serverId == null || cache('portfolio')['tableEditing'] != 1) {
      throw StateError('Подключи приложение к обновлённому серверу таблиц.');
    }
    final id = uuid.v4();
    local.enqueue('grid:$id', '/api/native/command', {
      'requestId': id,
      'serverId': serverId,
      'deviceId': deviceId,
      'module': 'portfolio',
      'action': action,
      'input': input,
    });
    status = 'Ячейка сохранена на устройстве · ожидает синхронизации';
    notifyListeners();
    requestAutoSync();
  }

  List<Json> gridColumns(String table, {bool archived = false}) {
    final cached = cache('portfolio');
    final columns = {
      for (final c in rows(
        object(cached['tableDefinitions'])[table] ?? defaultGridColumns[table],
      ))
        c['id']: Map<String, dynamic>.from(c),
    };
    for (final c in rows(object(cached['tableColumns'])[table])) {
      columns[c['id']] = Map<String, dynamic>.from(c);
    }
    for (final queued in pending) {
      final body = object(queued['body']), input = object(body['input']);
      if (body['module'] != 'portfolio' || input['table'] != table) continue;
      if (body['action'] == 'createColumn') {
        columns[input['id']] = {
          ...input,
          'custom': true,
          'archived': false,
          'visible': true,
          'revision': 1,
        };
      }
      if (body['action'] == 'updateColumn' &&
          columns.containsKey(input['id'])) {
        columns[input['id']] = {
          ...columns[input['id']]!,
          ...input,
          'revision': (input['expectedRevision'] as int) + 1,
        };
      }
    }
    return columns.values
        .where((c) => archived || c['archived'] != true)
        .toList();
  }

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
    for (final queued in pending) {
      final body = object(queued['body']), input = object(body['input']);
      if (body['module'] != 'portfolio' ||
          body['action'] != 'editCells' ||
          input['table'] != collection) {
        continue;
      }
      final key = '$prefix:${input['id']}';
      final previous = items[key];
      if (previous == null) continue;
      final row = Map<String, dynamic>.from(previous),
          custom = Map<String, dynamic>.from(object(previous['customValues']));
      final columns = gridColumns(collection, archived: true);
      for (final cell in rows(input['changes'])) {
        final column = columns
            .where((c) => c['id'] == cell['columnId'])
            .firstOrNull;
        if (column == null) continue;
        if (column['custom'] == true) {
          custom[cell['columnId'].toString()] = cell['value'];
        } else {
          row[cell['columnId'].toString()] = cell['value'];
        }
      }
      items[key] = {...row, 'customValues': custom};
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
      final queued = pending
          .where(
            (q) =>
                q['route'] == '/api/timer' &&
                object(q['body'])['action'] == 'finish' &&
                object(object(q['body'])['input'])['sessionId'] ==
                    session['id'],
          )
          .firstOrNull;
      if (queued != null &&
          (local.get('timerChainConflict') == true ||
              pending.any(
                (q) => q['route'] == '/api/timer' && q['state'] == 'conflict',
              ))) {
        continue;
      }
      if (fact != null && queued?['state'] != 'conflict') {
        facts[session['id'].toString()] = {
          ...fact,
          if (queued != null) 'pending': true,
        };
      }
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
    return pomodoroTargetsOn(pomodoroRows, day).map((n) {
      final facts = pomodoroFacts
          .where((f) => f['date'] == day && f['workRef'] == n['workRef'])
          .toList();
      return {
        ...n,
        'actualPomodoros': facts.length,
        'pendingPomodoros': facts.where((f) => f['pending'] == true).length,
      };
    }).toList();
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
    if (durableTimer) {
      _queueSharedAction(action, input);
      return;
    }
    if (_sharedActionInFlight) return;
    if (isLocal) throw StateError('Сначала заверши таймер этого устройства.');
    if (!online) {
      throw StateError(
        'Для общего сеанса нужна связь с сервером. Для самостоятельного учёта выбери таймер устройства.',
      );
    }
    _sharedActionInFlight = true;
    notifyListeners();
    try {
      if (timerPending) await _recoverTimerCommand();
      final current = active;
      if ([
        'pause',
        'resume',
        'extend',
        'finish',
        'cancel',
        'leisure',
      ].contains(action)) {
        if (current == null || current['id'] != input['sessionId']) {
          throw StateError(
            'Этот сеанс уже завершён или изменён. Таймер обновлён.',
          );
        }
        if (action == 'pause' && current['status'] == 'paused' ||
            action == 'resume' && current['status'] == 'running') {
          return;
        }
      }
      for (var attempt = 0; attempt < 2; attempt++) {
        final command = {
          'action': action,
          'input': {
            ...input,
            'requestId': uuid.v4(),
            'expectedRevision': cache('timer')['revision'] ?? 0,
          },
        };
        local.atomic(() {
          local.set('pendingTimer', command);
          local.set('pendingTimerServerId', serverId);
        });
        try {
          await checkPendingTimer();
          return;
        } on ApiFailure catch (e) {
          // This click expresses pause/resume for this exact session. Retry once
          // after a definite version rejection; never replay finish or extend.
          if (attempt != 0 ||
              e.status != 409 ||
              timerPending ||
              !['pause', 'resume'].contains(action) ||
              active?['id'] != input['sessionId']) {
            rethrow;
          }
          if (action == 'pause' && active?['status'] == 'paused' ||
              action == 'resume' && active?['status'] == 'running') {
            return;
          }
        }
      }
    } finally {
      _sharedActionInFlight = false;
      notifyListeners();
    }
  }

  void _captureTimer(Json result) {
    if ((result['revision'] as int? ?? 0) >=
        (local.snapshot('timer')['revision'] as int? ?? 0)) {
      local.capture('timer', result);
    }
  }

  void _clearTimerProjectionIfAcknowledged() {
    if (!pending.any((q) => q['route'] == '/api/timer') &&
        local.get('pendingTimer') == null) {
      local.remove('optimisticTimer');
      local.remove('timerChainConflict');
    }
  }

  void _queueSharedAction(String action, Json input) {
    if (isLocal) {
      throw StateError('Сначала заверши таймер этого устройства.');
    }
    if (serverId == null) {
      throw StateError('Один раз подключи приложение к своему серверу.');
    }
    final before = cache('timer');
    final current = before['active'] is Map ? object(before['active']) : null;
    if (action == 'pause' && current?['status'] == 'paused' ||
        action == 'resume' && current?['status'] == 'running') {
      return;
    }
    final at = now;
    final id = uuid.v4();
    final fields = <String, dynamic>{
      ...input,
      'requestId': id,
      'expectedRevision': before['revision'] ?? 0,
      'occurredAt': at,
      if (['start', 'startBreak'].contains(action)) 'newSessionId': uuid.v4(),
    };
    final projected = projectTimer(before, action, fields, at);
    // Command, complete projected session and screen state survive one SQLite transaction.
    local.atomic(() {
      local.db.execute(
        'INSERT INTO outbox(id,entity,route,body,server_id,created) VALUES(?,?,?,?,?,?)',
        [
          id,
          'timer:$id',
          '/api/timer',
          jsonEncode({'action': action, 'input': fields}),
          serverId,
          local.nextOrder(),
        ],
      );
      local.set('optimisticTimer', projected);
      if (['finish', 'cancel'].contains(action)) {
        final completed = rows(projected['sessions'])
            .firstWhere((s) => s['id'] == fields['sessionId']);
        final history = rows(local.get('sharedLocalHistory'))
            .where((s) => s['id'] != completed['id'])
            .toList();
        local.set('sharedLocalHistory', [...history, completed]);
      }
      local.set('lastLocalSaveAt', DateTime.now().toUtc().toIso8601String());
    });
    status = 'Сохранено на устройстве · ожидает синхронизации';
    notifyListeners();
    requestAutoSync();
  }

  Future<void> _recoverTimerCommand() async {
    try {
      await checkPendingTimer();
    } on ApiFailure {
      // Only a definite rejection with a refreshed snapshot may release the slot.
      if (timerPending) rethrow;
    }
  }

  Future<void> checkPendingTimer() {
    if (durableTimer && local.get('pendingTimer') == null) {
      return synchronize();
    }
    if (_timerCheck != null) return _timerCheck!;
    if (!timerPending) return Future.value();
    final operation = _sendPendingTimer().whenComplete(() {
      _timerCheck = null;
      notifyListeners();
    });
    _timerCheck = operation;
    notifyListeners();
    return operation;
  }

  Future<void> _sendPendingTimer() async {
    final command = local.get('pendingTimer');
    if (command == null) return;
    final expectedServer = local.get('pendingTimerServerId') ?? serverId;
    final commandBase = base;
    // Check the installation before replay, including commands from older clients.
    final context = await request(
      '/api/offline/connect',
      body: {'deviceId': deviceId},
    );
    if (expectedServer == null ||
        context['serverId'] != expectedServer ||
        commandBase != base) {
      throw ApiFailure(
        'Команда принадлежит другой установке сервера. Исходник сохранён.',
        409,
      );
    }
    try {
      final result = await request('/api/timer', body: object(command));
      if (commandBase != base) {
        throw StateError(
          'Адрес сервера изменился. Команда сохранена для проверки.',
        );
      }
      local.atomic(() {
        _captureTimer(result);
        local.remove('pendingTimer');
        local.remove('pendingTimerServerId');
        local.remove('timerConflict');
      });
      _clearTimerProjectionIfAcknowledged();
      notifyListeners();
    } on ApiFailure catch (e) {
      if ([400, 409, 422].contains(e.status)) {
        local.set('timerConflict', e.message);
        final latest = await request('/api/timer');
        if (commandBase != base) rethrow;
        local.atomic(() {
          final history = object(local.get('timerCommandHistory'));
          history[object(object(command)['input'])['requestId'].toString()] = {
            'command': command,
            'serverId': expectedServer,
            'status': 'rejected',
            'httpStatus': e.status,
            'error': e.message,
            'at': DateTime.now().toUtc().toIso8601String(),
          };
          local.set('timerCommandHistory', history);
          _captureTimer(latest);
          local.remove('pendingTimer');
          local.remove('pendingTimerServerId');
          local.remove('timerConflict');
        });
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> abandonTimerCommand() async {
    // Reconcile the immutable command instead of silently dropping it.
    await checkPendingTimer();
  }

  Future<void> resolveConflict(Json item, {required bool apply}) async {
    if (!apply) {
      local.resolve(item['id'].toString());
      _clearTimerProjectionIfAcknowledged();
      notifyListeners();
      requestAutoSync();
      return;
    }
    final body = object(item['body']);
    if (item['route'] == '/api/timer') {
      throw StateError(
        'Команды времени нельзя применять поверх другого сеанса. Сохрани исходник локально или повтори исходную команду.',
      );
    }
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
          if (body['action'] == 'editCells' ||
              body['action'] == 'updateColumn') {
            final fresh = await request('/api/portfolio');
            if (item['server_id'] != serverId) {
              throw StateError('Правка связана с другой установкой.');
            }
            local.capture('portfolio', fresh);
            if (body['action'] == 'editCells') {
              current = rows(fresh[input['table'].toString()])
                  .where((r) => r['id'] == input['id'])
                  .firstOrNull;
              if (current == null) {
                throw StateError(
                  'Строка не найдена. Исходная правка сохранена.',
                );
              }
              final definitions = rows(
                object(fresh['tableDefinitions'])[input['table']],
              );
              input['changes'] = [
                for (final change in rows(input['changes']))
                  (() {
                    final col = definitions
                        .where((c) => c['id'] == change['columnId'])
                        .firstOrNull;
                    if (col == null) {
                      throw StateError('Сначала восстанови столбец из архива.');
                    }
                    return {
                      ...change,
                      'before': col['custom'] == true
                          ? object(current!['customValues'])[col['id']]
                          : current![col['id']],
                    };
                  })(),
              ];
            } else {
              final column = rows(object(fresh['tableColumns'])[input['table']])
                  .where((c) => c['id'] == input['id'])
                  .firstOrNull;
              if (column == null) {
                throw StateError('Столбец не найден. Исходник сохранён.');
              }
              input['expectedRevision'] = column['revision'];
            }
            break;
          }
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
    requestAutoSync();
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
    int? leisureUntil,
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
        leisureUntil: leisureUntil,
      );
      if (['finish', 'cancel'].contains(action)) {
        local.finishLocal(changed, serverId);
        requestAutoSync();
      } else {
        local.set('localActive', changed);
      }
      notifyListeners();
    } else {
      await sharedAction(action, {
        'sessionId': s['id'],
        if (action == 'finish') 'observation': observation,
        'workedSeconds': ?workedSeconds,
        'leisureUntil': ?leisureUntil,
      });
    }
  }

  List<Json> get writingEntries {
    final entries = <String, Json>{};
    void merge(Json article) {
      final id = article['id'].toString();
      final original = cache('writing:$id');
      final previous = entries[id];
      final metadata =
          (original['revision'] as int? ?? 0) >=
              (previous?['revision'] as int? ?? 0)
          ? {...?previous, ...original}
          : previous!;
      entries[id] = {
        ...metadata,
        ...article,
        'trashedAt': metadata.containsKey('trashedAt')
            ? metadata['trashedAt']
            : article['trashedAt'],
        'favorite': metadata.containsKey('favorite')
            ? metadata['favorite']
            : article['favorite'] ?? false,
      };
    }

    for (final article in rows(cache('writing')['entries'])) {
      merge(article);
    }
    for (final draft in local.drafts.where(
      (d) => d['entity'].toString().startsWith('composer:'),
    )) {
      merge(object(draft['body']));
    }
    for (final draft in local.drafts.where(
      (d) => d['entity'].toString().startsWith('writing:'),
    )) {
      final article = object(draft['body']);
      entries[article['id'].toString()] = {
        ...?entries[article['id'].toString()],
        ...article,
      };
    }
    return entries.values.toList();
  }

  void saveWriting(Json article, {bool trash = false}) {
    final archive = cache('writing')['instanceId'];
    if (archive == null) throw StateError('Сначала загрузи архив с сервера.');
    final original = cache('writing:${article['id']}');
    local.enqueue(
      'writing:${article['id']}',
      '/api/writing',
      {
        'action': trash ? 'saveAndTrash' : 'save',
        'requestId': uuid.v4(),
        'instanceId': archive,
        'id': article['id'],
        'expectedRevision': original['revision'] ?? 0,
        'title': article['title'],
        'date': article['date'],
        'status': article['status'],
        'document': article['document'],
        if (article['favorite'] is bool) 'favorite': article['favorite'],
      },
      draft: {
        ...article,
        'trashedAt': trash ? DateTime.now().toUtc().toIso8601String() : null,
      },
    );
    notifyListeners();
    requestAutoSync();
  }

  void restoreWriting(String id) {
    if (pending.any((p) => p['entity'] == 'writing:$id')) {
      throw StateError('Дождись синхронизации удаления перед восстановлением.');
    }
    final original = cache('writing:$id');
    if (original['trashedAt'] == null) {
      throw StateError('Сначала загрузи удалённую запись с сервера.');
    }
    local.enqueue(
      'writing:$id',
      '/api/writing',
      {
        'action': 'restore',
        'requestId': uuid.v4(),
        'instanceId': cache('writing')['instanceId'],
        'id': id,
        'expectedRevision': original['revision'],
      },
      draft: {...original, 'trashedAt': null},
    );
    notifyListeners();
    requestAutoSync();
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
