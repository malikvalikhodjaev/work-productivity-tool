import 'domain.dart';
import 'time_types.dart';

void validateNormTimeType(Json input) {
  if (input.containsKey('workType') &&
      !validTimeTypeSelection(input['workType'])) {
    throw ArgumentError('Выбери типы времени норматива.');
  }
}

void validatePomodoroCapacity(Json input) {
  final date = input['date'];
  if (date is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
      DateTime.tryParse('${date}T12:00:00Z')
              ?.toIso8601String()
              .substring(0, 10) !=
          date) {
    throw ArgumentError('Дата: YYYY-MM-DD.');
  }
  final limit = input['limit'];
  if (limit != null && (limit is! int || limit < 1 || limit > 1440)) {
    throw ArgumentError(
      'Дневной лимит: целое число от 1 до 1440, либо пусто для снятия.',
    );
  }
}

int? pomodoroCapacityOn(List<Json> rules, String date) {
  Json? selected;
  for (final row in rules) {
    if (row['date'].toString().compareTo(date) <= 0 &&
        (selected == null ||
            row['date'].toString().compareTo(selected['date'].toString()) >
                0)) {
      selected = row;
    }
  }
  return selected?['limit'] as int?;
}

Json pomodoroCapacitySummary(
  List<Json> targets,
  List<Json> rules,
  String date, {
  Json? candidate,
}) {
  final effective = candidate == null
      ? targets
      : [
          ...targets.where((t) => t['workRef'] != candidate['workRef']),
          candidate,
        ];
  final planned = effective.fold<int>(
    0,
    (sum, t) => sum + (t['target'] as int? ?? 0),
  );
  final limit = pomodoroCapacityOn(rules, date),
      over = limit != null && planned > limit;
  return {
    'date': date,
    'planned': planned,
    'limit': limit,
    'over': over,
    'message': limit == null
        ? 'План: $planned помидорок · дневной лимит не задан.'
        : over
        ? 'В плане сейчас $planned помидорок, а твой лимит — $limit в день. Превышение: ${planned - limit}. Проверь план с учётом своих сил.'
        : 'План: $planned помидорок · твой лимит: $limit в день.',
  };
}

String pomodoroDate(int utcMs) => DateTime.fromMillisecondsSinceEpoch(
  utcMs,
  isUtc: true,
).add(const Duration(hours: 5)).toIso8601String().substring(0, 10);
String pomodoroShift(String date, int days) =>
    DateTime.parse('${date}T12:00:00Z')
        .add(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
String pomodoroMonday(String date) =>
    pomodoroShift(date, 1 - DateTime.parse('${date}T12:00:00Z').weekday);

Json? pomodoroFact(Json session) {
  if (session['id'] is! String ||
      (session['id'] as String).isEmpty ||
      session['status'] != 'finished' ||
      session['phase'] != 'work' ||
      session['mode'] != 'pomodoro' ||
      session['completedPomodoros'] != 1 ||
      session['syncResolution'] == 'excluded') {
    return null;
  }
  final stamp = DateTime.tryParse(session['finishedAt']?.toString() ?? '');
  if (stamp == null) return null;
  return {
    'sessionId': session['id'],
    'workRef': session['workRef'],
    'date': pomodoroDate(stamp.millisecondsSinceEpoch),
    'count': 1,
  };
}

List<Json> pomodoroTargetsOn(List<Json> records, String date) {
  final selected = <String, Json>{};
  for (final row in records) {
    final start = row['date'].toString();
    if (start != date &&
        !(row['repeat'] == 'daily' && start.compareTo(date) <= 0)) {
      continue;
    }
    final previous = selected[row['workRef']];
    if (previous == null || start.compareTo(previous['date'].toString()) > 0) {
      selected[row['workRef'].toString()] = row;
    }
  }
  return selected.values
      .where((n) => n['target'] != null)
      .map(
        (n) => <String, dynamic>{...n, 'sourceDate': n['date'], 'date': date},
      )
      .toList();
}

List<Json> pomodoroWeekRows(List<Json> targets, List<Json> facts, String week) {
  final start = pomodoroMonday(week), end = pomodoroShift(start, 6);
  final groups = <String, Json>{};
  final effective = [
    for (var i = 0; i < 7; i++)
      ...pomodoroTargetsOn(targets, pomodoroShift(start, i)),
  ];
  for (final n in effective.where(
    (n) =>
        n['target'] != null &&
        n['date'].toString().compareTo(start) >= 0 &&
        n['date'].toString().compareTo(end) <= 0,
  )) {
    final key = '${n['workRef']}\u0000${n['title']}';
    final row = groups.putIfAbsent(
      key,
      () => {
        'title': n['title'],
        'workRef': n['workRef'],
        'days': <Json>[],
        'target': 0,
        'actualPomodoros': 0,
      },
    );
    final count = facts
        .where((f) => f['date'] == n['date'] && f['workRef'] == n['workRef'])
        .map((f) => f['sessionId'])
        .toSet()
        .length;
    (row['days'] as List<Json>).add({
      'date': n['date'],
      'target': n['target'],
      'actualPomodoros': count,
    });
    row['target'] = (row['target'] as int) + (n['target'] as int);
    row['actualPomodoros'] = (row['actualPomodoros'] as int) + count;
  }
  return groups.values.toList();
}
