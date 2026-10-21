import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'active_timer_conflict.dart';
import 'domain.dart';
import 'durable_timer.dart';
import 'focus_backup.dart';
import 'pomodoro_plan.dart';
import 'repository.dart';

/// Device-only edition: committed snapshots, no fake server and no outbox.
class FocusRepository extends DashboardRepository {
  FocusRepository(super.local, {super.client}) {
    local.atomic(() {
      if (local.get('focusArchiveId') == null) {
        local.set('focusArchiveId', uuid.v4());
      }
      if (local.snapshot('timer').isEmpty) {
        local.capture('timer', {
          'revision': 0,
          'settings': timerDefaults,
          'active': null,
          'sessions': <Json>[],
          'cycleCount': 0,
          'offlineCommands': true,
        });
      }
      if (local.snapshot('workspace').isEmpty) {
        local.capture('workspace', {
          'workItems': <Json>[],
          'cases': <Json>[],
          'entities': <Json>[],
        });
      }
      if (local.snapshot('dailyNorms').isEmpty) {
        local.capture('dailyNorms', {
          'norms': <Json>[],
          'checks': <Json>[],
          'pomodoroTargets': <Json>[],
        });
      }
      local.set('serverOffset', 0);
      local.set('automaticSync', false);
    });
    status = 'Сохранено на устройстве';
  }

  @override
  String get serverId => local.get('focusArchiveId') as String;
  @override
  bool get timerOnly => true;
  @override
  bool get durableTimer => true;
  @override
  bool get automaticSync => false;
  @override
  String get timerStrategy => 'shared';
  @override
  void requestAutoSync() {}
  @override
  void startPolling() {}
  @override
  Future<void> synchronize() async {}

  @override
  Future<void> sharedAction(String action, Json input) async {
    if (['start', 'startBreak'].contains(action) && active != null) {
      throw ActiveTimerConflict(active!);
    }
    final before = cache('timer');
    if (action == 'pause' && active?['status'] == 'paused' ||
        action == 'resume' && active?['status'] == 'running') {
      return;
    }
    final projected = projectTimer(before, action, {
      ...input,
      if (['start', 'startBreak'].contains(action))
        'settings': input['settings'] ?? settings,
      if (['start', 'startBreak'].contains(action)) 'newSessionId': uuid.v4(),
    }, now);
    projected['settings'] = settings;
    local.atomic(() {
      local.capture('timer', projected);
      local.set('lastLocalSaveAt', DateTime.now().toUtc().toIso8601String());
    });
    status = 'Сохранено на устройстве';
    notifyListeners();
  }

  @override
  void nativeSave(
    String module,
    String action,
    Json input,
    String entity, {
    Json? draft,
    dynamic expectedUpdatedAt,
    dynamic expectedTarget,
  }) {
    if (module == 'workspace' && action == 'saveWorkItem') {
      final title = (input['title'] ?? '').toString();
      final note = (input['description'] ?? '').toString();
      if (title.trim().isEmpty || title.length > 300 || note.length > 12000) {
        throw ArgumentError('Название: 1–300 знаков; описание: до 12000.');
      }
      final snapshot = cache('workspace');
      final items = rows(snapshot['workItems']);
      final id = input['id']?.toString() ?? uuid.v4();
      final old = items.where((row) => row['id'] == id).firstOrNull;
      if (input['create'] == true && old != null) {
        throw StateError('Работа уже существует.');
      }
      if (old != null && input['expectedRevision'] != old['revision']) {
        throw StateError(
          'Работа изменена. Открой её снова; исходный текст сохранён.',
        );
      }
      final next = <String, dynamic>{
        ...?old,
        ...input,
        'id': id,
        'title': title,
        'description': note,
        'kind': 'work',
        'stage': input['stage'] ?? old?['stage'] ?? 'planned',
        'revision': (old?['revision'] as int? ?? 0) + 1,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'history': [
          ...rows(old?['history']),
          if (old != null) {...old}..remove('history'),
        ],
      };
      final changed = [...items.where((row) => row['id'] != id), next];
      local.atomic(
        () => local.capture('workspace', {
          ...snapshot,
          'workItems': changed,
          'entities': [
            for (final row in changed) {...row, 'ref': 'work:${row['id']}'},
          ],
        }),
      );
    } else if (module == 'pomodoroCapacity' && action == 'save') {
      validatePomodoroCapacity(input);
      final snapshot = cache('dailyNorms'),
          records = rows(snapshot['pomodoroCapacities']);
      final previous = records
          .where((r) => r['date'] == input['date'])
          .firstOrNull;
      if (expectedUpdatedAt != previous?['updatedAt']) {
        throw StateError('Лимит изменён. Открой настройки снова.');
      }
      final next = <String, dynamic>{
        ...input,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'revisions': [
          ...rows(previous?['revisions']),
          if (previous != null) {...previous}..remove('revisions'),
        ],
      };
      local.atomic(
        () => local.capture('dailyNorms', {
          ...snapshot,
          'pomodoroCapacities': [
            ...records.where((r) => r['date'] != input['date']),
            next,
          ],
        }),
      );
    } else if (module == 'pomodoroTarget' && action == 'save') {
      final date = input['date']?.toString() ?? '';
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          DateTime.tryParse('${date}T12:00:00Z')
                  ?.toIso8601String()
                  .substring(0, 10) !=
              date) {
        throw ArgumentError('Укажи дату YYYY-MM-DD.');
      }
      final title = (input['title'] ?? '').toString();
      final ref = input['workRef']?.toString();
      if (!rows(cache('workspace')['entities'])
          .any((row) => row['ref'] == ref)) {
        throw ArgumentError('Выбери существующую работу.');
      }
      if (title.trim().isEmpty ||
          title.length > 300 ||
          input['target'] != null &&
              (input['target'] is! int ||
                  input['target'] < 1 ||
                  input['target'] > 1440)) {
        throw ArgumentError(
          'Назови норматив; количество — 1–1440 или пусто для снятия.',
        );
      }
      final snapshot = cache('dailyNorms'),
          targets = rows(snapshot['pomodoroTargets']);
      final old = targets
          .where((row) => row['workRef'] == ref && row['date'] == date)
          .firstOrNull;
      if (input['create'] == true &&
          pomodoroTargetsOn(
            targets,
            date,
          ).any((row) => row['workRef'] == ref)) {
        throw StateError(
          'Для этой работы уже есть норматив. Используй карандаш или выбери другую работу.',
        );
      }
      if (expectedUpdatedAt != old?['updatedAt']) {
        throw StateError('Норматив изменён. Открой строку снова.');
      }
      final next = <String, dynamic>{
        ...input,
        'repeat': 'daily',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'history': [
          ...rows(old?['history']),
          if (old != null) {...old}..remove('history'),
        ],
      };
      local.atomic(
        () => local.capture('dailyNorms', {
          ...snapshot,
          'pomodoroTargets': [
            ...targets.where(
              (row) => row['date'] != date || row['workRef'] != ref,
            ),
            next,
          ],
        }),
      );
    } else {
      throw StateError('В Focus & Norms доступны работы, таймер и нормативы.');
    }
    status = 'Сохранено на устройстве';
    notifyListeners();
  }

  Map<String, int> get workedMillisecondsByDay {
    final result = <String, int>{};
    for (final session in rows(
      cache('timer')['sessions'],
    ).where((s) => s['status'] == 'finished' && s['phase'] == 'work')) {
      for (final interval in rows(session['intervals'])) {
        var cursor = interval['start'] as int;
        final end = interval['end'] as int;
        while (cursor < end) {
          final day = pomodoroDate(cursor);
          final boundary =
              DateTime.parse('${day}T00:00:00Z').millisecondsSinceEpoch +
              86400000 -
              5 * 3600000;
          final cut = math.min(end, boundary);
          result[day] = (result[day] ?? 0) + cut - cursor;
          cursor = cut;
        }
      }
    }
    return result;
  }

  @override
  Future<String> exportLocal(String folder) async {
    final directory = Directory('$folder/exports');
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/focus-norms-backup-${DateTime.now().millisecondsSinceEpoch}-${uuid.v4()}.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'format': 'focus-norms-backup',
        'version': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'archiveId': serverId,
        'workspace': cache('workspace'),
        'dailyNorms': cache('dailyNorms'),
        'timer': cache('timer'),
        'settings': settings,
      }),
    );
    return file.path;
  }

  Future<String> restoreBackup(String raw, String folder) async {
    if (active != null) {
      throw StateError('Сначала учти или отмени текущий сеанс.');
    }
    String signature() => jsonEncode([
      serverId,
      cache('workspace'),
      cache('dailyNorms'),
      cache('timer'),
      settings,
    ]);
    final before = signature();
    final data = validateFocusBackup(raw, now);
    final previous = await exportLocal(folder);
    final source = File('$folder/imported-backup-${uuid.v4()}.json');
    await source.writeAsString(raw);
    if (before != signature()) {
      throw StateError(
        'Данные изменились во время восстановления. Открой копию снова. Прежние записи сохранены.',
      );
    }
    local.atomic(() {
      local.capture('workspace', object(data['workspace']));
      local.capture('dailyNorms', object(data['dailyNorms']));
      local.capture('timer', object(data['timer']));
      local.set('focusArchiveId', data['archiveId']);
      local.set('timerSettings', data['settings']);
      local.set('focusLastRestoreBackup', previous);
    });
    status = 'Копия восстановлена. Прежние данные: $previous';
    notifyListeners();
    return previous;
  }
}
