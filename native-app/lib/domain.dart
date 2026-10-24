import 'dart:math';

import 'package:uuid/uuid.dart';

typedef Json = Map<String, dynamic>;
const uuid = Uuid();
const timerDefaults = <String, dynamic>{
  'workMinutes': 25,
  'shortBreakMinutes': 5,
  'longBreakMinutes': 15,
  'longBreakEvery': 4,
};
String today() => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 5))
    .toIso8601String()
    .substring(0, 10);
String weekStart([String? date]) {
  final value = date ?? today();
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
    throw ArgumentError('Укажи дату недели в формате ГГГГ-ММ-ДД.');
  }
  return parsed
      .subtract(Duration(days: parsed.weekday - 1))
      .toIso8601String()
      .substring(0, 10);
}

String weekRange(String week) {
  final end = DateTime.parse('${week}T00:00:00Z')
      .add(const Duration(days: 6))
      .toIso8601String()
      .substring(0, 10);
  return '$week — $end';
}

List<Json> rows(dynamic value) => (value is List ? value : const [])
    .whereType<Map>()
    .map((r) => Map<String, dynamic>.from(r))
    .toList();
Json object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
String caption(Json session) => session['phase'] == 'work'
    ? (session['workRef']?.toString().startsWith('case:') == true
              ? 'Working on a problem: '
              : 'Working on: ') +
          session['title'].toString()
    : session['title'].toString();
int elapsedMs(Json s, int now) {
  final past = rows(s['intervals']).fold<int>(
    0,
    (n, i) => n + (i['end'] as num).toInt() - (i['start'] as num).toInt(),
  );
  final run = s['status'] == 'running'
      ? max(0, now - (s['runningSince'] as num).toInt())
      : 0;
  return min(
    86400000,
    past +
        (s['mode'] == 'pomodoro'
            ? min(run, max(0, (s['plannedMs'] as num).toInt() - past))
            : run),
  );
}

bool pomodoroExpired(Json? s, int now) =>
    s != null &&
    s['mode'] == 'pomodoro' &&
    elapsedMs(s, now) >= (s['plannedMs'] as num);

bool inLeisure(Json? s) => s?['leisure'] is Map;
bool leisureDue(Json? s, int now) =>
    inLeisure(s) && object(s?['leisure'])['until'] <= now;
String leisureKey(Json s) =>
    '${s['id']}:${object(s['leisure'])['start']}:${object(s['leisure'])['until']}';
String leisureTime(Json s) => DateTime.fromMillisecondsSinceEpoch(
  object(s['leisure'])['until'] as int,
  isUtc: true,
).add(const Duration(hours: 5)).toIso8601String().substring(11, 16);
int leisureElapsedMs(Json s, int now) =>
    rows(
      s['leisureIntervals'],
    ).fold<int>(0, (sum, i) => sum + (i['end'] as int) - (i['start'] as int)) +
    (inLeisure(s) ? max(0, now - (object(s['leisure'])['start'] as int)) : 0);

String clockOf(Json s, int now, {bool workOnly = false}) {
  final ms = !workOnly && inLeisure(s)
      ? max(0, (object(s['leisure'])['until'] as int) - now)
      : s['mode'] == 'pomodoro'
      ? max(0, (s['plannedMs'] as num).toInt() - elapsedMs(s, now))
      : elapsedMs(s, now);
  final total = ms ~/ 1000;
  final h = total ~/ 3600;
  return '${h > 0 ? '$h:' : ''}${(total ~/ 60 % 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
}

Json newLocalSession({
  required String title,
  String? workRef,
  String? metricId,
  String allocation = 'unclassified',
  String workType = '',
  String mode = 'pomodoro',
  String phase = 'work',
  Json settings = timerDefaults,
  required int now,
}) {
  validateSettings(settings);
  if (title.trim().isEmpty || title.length > 300) {
    throw ArgumentError('Название: 1–300 символов.');
  }
  final stamp = DateTime.fromMillisecondsSinceEpoch(
    now,
    isUtc: true,
  ).toIso8601String();
  final minutes = phase == 'work'
      ? settings['workMinutes']
      : phase == 'long_break'
      ? settings['longBreakMinutes']
      : settings['shortBreakMinutes'];
  return {
    'id': uuid.v4(),
    'title': title,
    'workRef': phase == 'work' ? workRef : null,
    'metricId': phase == 'work' ? metricId : null,
    'allocation': phase == 'work'
        ? (metricId == null ? allocation : 'assigned')
        : 'break',
    'workType': workType.isEmpty ? null : workType,
    'mode': mode,
    'phase': phase,
    'status': 'running',
    'settings': Map<String, dynamic>.from(settings),
    'plannedMs': mode == 'pomodoro' ? (minutes as int) * 60000 : null,
    'startedAt': stamp,
    'finishedAt': null,
    'updatedAt': stamp,
    'runningSince': now,
    'intervals': <Json>[],
    'events': [
      {
        'action': phase == 'work' ? 'start' : 'startBreak',
        'at': stamp,
        'elapsedSeconds': 0,
      },
    ],
    'completedPomodoros': 0,
  };
}

void validateSettings(Json settings) {
  for (final field in [
    'workMinutes',
    'shortBreakMinutes',
    'longBreakMinutes',
  ]) {
    if (settings[field] is! int ||
        settings[field] < 1 ||
        settings[field] > 240) {
      throw ArgumentError('Интервалы: целые минуты от 1 до 240.');
    }
  }
  if (settings['longBreakEvery'] is! int ||
      settings['longBreakEvery'] < 1 ||
      settings['longBreakEvery'] > 20) {
    throw ArgumentError('Цикл: 1–20 помидорок.');
  }
}

Json changeLocalSession(
  Json source,
  String action,
  int now, {
  String observation = '',
  int? workedSeconds,
  int? leisureUntil,
}) {
  final s = {
    ...source,
    'intervals': rows(source['intervals']),
    'events': rows(source['events']),
  };
  if (!['running', 'paused'].contains(s['status'])) {
    throw StateError('Сеанс завершён.');
  }
  if (now < DateTime.parse(s['updatedAt'] as String).millisecondsSinceEpoch) {
    throw StateError(
      'Часы устройства переведены назад. Проверь время; сеанс сохранён.',
    );
  }
  final intervals = rows(s['intervals']);
  if (s['status'] == 'running') {
    final saved =
        intervals.fold<int>(0, (n, i) => n + i['end'] as int) -
        intervals.fold<int>(0, (n, i) => n + i['start'] as int);
    final amount = elapsedMs(s, now) - saved;
    if (amount > 0) {
      intervals.add({
        'start': s['runningSince'],
        'end': (s['runningSince'] as int) + amount,
      });
    }
    s['runningSince'] = null;
  }
  s['intervals'] = intervals;
  final stamp = DateTime.fromMillisecondsSinceEpoch(
    now,
    isUtc: true,
  ).toIso8601String();
  if (action == 'leisure') {
    if (s['phase'] != 'work') {
      throw StateError('Leisure доступен из рабочего сеанса.');
    }
    if (leisureUntil == null ||
        leisureUntil <= now ||
        leisureUntil > now + 86400000) {
      throw ArgumentError(
        'Выбери время окончания Leisure в следующие 24 часа.',
      );
    }
    if (s['mode'] == 'pomodoro' &&
        elapsedMs({...s, 'status': 'paused'}, now) >= s['plannedMs']) {
      throw StateError('Сначала учти истёкшую помидорку или продли её.');
    }
    s['status'] = 'paused';
    s['leisure'] = {
      'start': object(source['leisure'])['start'] ?? now,
      'until': leisureUntil,
    };
  } else if (action == 'pause') {
    if (source['status'] != 'running') throw StateError('Сеанс уже на паузе.');
    s['status'] = 'paused';
  } else if (action == 'resume') {
    if (source['status'] != 'paused') throw StateError('Сеанс уже запущен.');
    if (s['mode'] == 'pomodoro' && elapsedMs(s, now) >= s['plannedMs']) {
      throw StateError('Интервал истёк. Заверши или продли его.');
    }
    s['status'] = 'running';
    s['runningSince'] = now;
  } else if (action == 'extend') {
    if (s['mode'] != 'pomodoro' || s['plannedMs'] + 300000 > 14400000) {
      throw StateError('Максимальный план — 240 минут.');
    }
    s['plannedMs'] += 300000;
    if (s['status'] == 'running') s['runningSince'] = now;
  } else if (['finish', 'cancel'].contains(action)) {
    if (observation.length > 10000) {
      throw ArgumentError('Наблюдения: текст до 10000 символов.');
    }
    final total = elapsedMs({...s, 'status': 'paused'}, now);
    if (workedSeconds != null) {
      if (workedSeconds < 0 ||
          workedSeconds * 1000 > total ||
          workedSeconds > 86400) {
        throw ArgumentError(
          'Факт не может превышать учтённое время или 24 часа.',
        );
      }
      var left = workedSeconds * 1000;
      final trimmed = <Json>[];
      for (final interval in intervals) {
        final amount = min(
          left,
          (interval['end'] as int) - (interval['start'] as int),
        );
        if (amount > 0) {
          trimmed.add({
            'start': interval['start'],
            'end': (interval['start'] as int) + amount,
          });
        }
        left -= amount;
      }
      s['intervals'] = trimmed;
    }
    s['status'] = action == 'finish' ? 'finished' : 'cancelled';
    s['finishedAt'] = stamp;
    s['observation'] = observation;
    s['completedPomodoros'] =
        action == 'finish' &&
            s['phase'] == 'work' &&
            s['mode'] == 'pomodoro' &&
            elapsedMs(s, now) >= s['plannedMs']
        ? 1
        : 0;
  } else {
    throw ArgumentError('Неизвестное действие.');
  }
  if (['resume', 'finish', 'cancel'].contains(action) && inLeisure(source)) {
    final l = object(source['leisure']);
    s['leisureIntervals'] = [
      ...rows(source['leisureIntervals']),
      {'start': l['start'], 'end': now, 'plannedUntil': l['until']},
    ];
    s['leisure'] = null;
  }
  s['updatedAt'] = stamp;
  (s['events'] as List).add({
    'action': action,
    'at': stamp,
    'elapsedSeconds': elapsedMs(s, now) / 1000,
    'workedSeconds': ?workedSeconds,
    'leisureUntil': ?leisureUntil,
  });
  return s;
}
