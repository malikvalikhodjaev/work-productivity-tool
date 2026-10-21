import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:file_selector_windows/file_selector_windows.dart';

import 'background.dart';
import 'domain.dart';
import 'pomodoro_plan.dart';

Future<String?> pickFocusBackup() async {
  if (Platform.isAndroid) {
    return BackgroundRuntime.channel.invokeMethod<String>('pickBackup');
  }
  final file = await FileSelectorWindows().openFile(
    acceptedTypeGroups: [
      const XTypeGroup(label: 'Focus & Norms JSON', extensions: ['json']),
    ],
  );
  if (file == null) return null;
  if (await file.length() > 8 * 1024 * 1024) {
    throw ArgumentError('Размер копии больше 8 МиБ.');
  }
  return file.readAsString();
}

bool _date(dynamic value) =>
    value is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
    DateTime.tryParse('${value}T12:00:00Z')
            ?.toIso8601String()
            .substring(0, 10) ==
        value;
bool _id(dynamic value) =>
    value is String &&
    RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
      caseSensitive: false,
    ).hasMatch(value);
void _require(bool condition, String message) {
  if (!condition) throw ArgumentError('Некорректная копия: $message');
}

Json validateFocusBackup(String raw, int now) {
  _require(utf8.encode(raw).length <= 8 * 1024 * 1024, 'размер больше 8 МиБ');
  final data = object(jsonDecode(raw));
  _require(
    data['format'] == 'focus-norms-backup' && data['version'] == 1,
    'нужен файл Focus & Norms версии 1',
  );
  _require(_id(data['archiveId']), 'ID архива');
  final captured = DateTime.tryParse(data['exportedAt']?.toString() ?? '')
      ?.millisecondsSinceEpoch;
  _require(captured != null && captured <= now + 300000, 'время создания');
  validateSettings(object(data['settings']));
  final workspace = object(data['workspace']),
      norms = object(data['dailyNorms']),
      timer = object(data['timer']);
  _require(
    workspace['workItems'] is List &&
        norms['pomodoroTargets'] is List &&
        timer['sessions'] is List,
    'списки работ, норм и сеансов',
  );
  final refs = <String>{}, ids = <String>{};
  for (final row in rows(workspace['workItems'])) {
    _require(
      _id(row['id']) && ids.add(row['id']),
      'повтор или неверный ID работы',
    );
    _require(
      row['title'] is String &&
          row['title'].trim().isNotEmpty &&
          row['title'].length <= 300,
      'название работы',
    );
    _require(
      row['description'] == null ||
          row['description'] is String && row['description'].length <= 12000,
      'описание',
    );
    _require(row['revision'] is int && row['revision'] >= 1, 'версия работы');
    refs.add('work:${row['id']}');
  }
  _require(
    rows(workspace['workItems']).length ==
        (workspace['workItems'] as List).length,
    'структура работы',
  );
  final ruleKeys = <String>{};
  for (final row in rows(norms['pomodoroTargets'])) {
    _require(
      refs.contains(row['workRef']) && _date(row['date']),
      'связь или дата норматива',
    );
    _require(
      ruleKeys.add('${row['date']}:${row['workRef']}'),
      'повтор норматива',
    );
    _require(
      row['title'] is String &&
          row['title'].trim().isNotEmpty &&
          row['title'].length <= 300,
      'название норматива',
    );
    _require(
      row['target'] == null ||
          row['target'] is int && row['target'] >= 1 && row['target'] <= 1440,
      'число помидорок',
    );
    _require(
      row['repeat'] == 'daily' ||
          row['repeat'] == 'once' ||
          row['repeat'] == null,
      'повторение нормы',
    );
  }
  _require(
    rows(norms['pomodoroTargets']).length ==
        (norms['pomodoroTargets'] as List).length,
    'структура норматива',
  );
  final capacities = norms['pomodoroCapacities'];
  _require(
    capacities == null || capacities is List,
    'структура дневных лимитов',
  );
  final capacityDays = <String>{};
  for (final rule in rows(capacities)) {
    validatePomodoroCapacity(rule);
    _require(capacityDays.add(rule['date']), 'повтор дневного лимита');
  }
  _require(
    capacities == null ||
        rows(capacities).length == (capacities as List).length,
    'структура дневного лимита',
  );
  final sessions = rows(timer['sessions']), sessionIds = <String>{};
  for (final s in sessions) {
    _require(
      _id(s['id']) && sessionIds.add(s['id']),
      'повтор или неверный ID сеанса',
    );
    _require(
      ['work', 'short_break', 'long_break'].contains(s['phase']) &&
          ['pomodoro', 'stopwatch'].contains(s['mode']) &&
          ['running', 'paused', 'finished', 'cancelled'].contains(s['status']),
      'тип или состояние сеанса',
    );
    _require(
      s['title'] is String && s['title'].length <= 300,
      'название сеанса',
    );
    _require(
      s['workRef'] == null || refs.contains(s['workRef']),
      'работа сеанса',
    );
    _require(
      s['observation'] == null ||
          s['observation'] is String && s['observation'].length <= 10000,
      'наблюдения',
    );
    _require(s['intervals'] is List, 'интервалы');
    _require(
      s['events'] is List &&
          DateTime.tryParse(s['startedAt']?.toString() ?? '') != null,
      'история и дата сеанса',
    );
    validateSettings(object(s['settings']));
    var previous = 0, total = 0;
    for (final interval in rows(s['intervals'])) {
      _require(
        interval['start'] is int && interval['end'] is int,
        'отметки интервала',
      );
      _require(
        interval['start'] >= previous &&
            interval['end'] >= interval['start'] &&
            interval['end'] <= now + 300000,
        'порядок интервалов',
      );
      previous = interval['end'];
      total += (interval['end'] as int) - (interval['start'] as int);
    }
    _require(
      rows(s['intervals']).length == (s['intervals'] as List).length,
      'структура интервала',
    );
    _require(
      s['mode'] != 'pomodoro' ||
          s['plannedMs'] is int &&
              s['plannedMs'] > 0 &&
              s['plannedMs'] <= 14400000,
      'план помидорки',
    );
    _require(
      s['completedPomodoros'] == 0 || s['completedPomodoros'] == 1,
      'счётчик помидорок',
    );
    _require(
      s['completedPomodoros'] != 1 ||
          s['status'] == 'finished' &&
              s['phase'] == 'work' &&
              s['mode'] == 'pomodoro' &&
              total >= s['plannedMs'],
      'подтверждение помидорки',
    );
    if (s['status'] == 'running') {
      _require(
        s['runningSince'] is int &&
            s['runningSince'] >= previous &&
            s['runningSince'] <= captured!,
        'начало отсчёта',
      );
    }
    if (['finished', 'cancelled'].contains(s['status'])) {
      _require(
        DateTime.tryParse(s['finishedAt']?.toString() ?? '') != null,
        'дата завершения',
      );
    }
  }
  _require(
    sessions.length == (timer['sessions'] as List).length,
    'структура сеанса',
  );
  final open = sessions
      .where((s) => ['running', 'paused'].contains(s['status']))
      .toList();
  _require(open.length <= 1, 'несколько активных сеансов');
  _require(
    open.isEmpty
        ? timer['active'] == null
        : timer['active'] is Map && timer['active']['id'] == open.single['id'],
    'активный сеанс',
  );
  if (open.isNotEmpty) {
    final source = open.single;
    final restored = source['status'] == 'running'
        ? changeLocalSession(source, 'pause', captured!)
        : source;
    timer['active'] = restored;
    timer['sessions'] = [
      for (final s in sessions)
        if (s['id'] == restored['id']) restored else s,
    ];
  }
  _require(
    timer['revision'] is int && timer['revision'] >= 0,
    'версия таймера',
  );
  return {
    ...data,
    'workspace': {
      ...workspace,
      'entities': [
        for (final row in rows(workspace['workItems']))
          {...row, 'ref': 'work:${row['id']}'},
      ],
    },
    'dailyNorms': norms,
    'timer': timer,
  };
}
