import 'dart:math';

import 'domain.dart';
import 'repository.dart';

const timeTypeLabels = {
  'investment': 'Investment · развитие',
  'productive': 'Productive · результат',
  'leisure': 'Leisure · отдых',
  'waste': 'Waste · потерянное',
  'unclassified': 'Без типа',
};

String timeType(dynamic value) =>
    switch (value?.toString().trim().toLowerCase()) {
      'investment' ||
      'investment time' ||
      'инвестиционное' ||
      'инвестиции' => 'investment',
      'productive' || 'productive time' || 'продуктивное' => 'productive',
      'leisure' || 'leasure' || 'leisure time' || 'отдых' => 'leisure',
      'waste' || 'wasted' || 'wasted time' || 'потерянное' => 'waste',
      _ => 'unclassified',
    };

Map<String, String> timeTypeOptions(dynamic previous) => {
  '': 'Не выбран',
  for (final e in timeTypeLabels.entries.where((e) => e.key != 'unclassified'))
    e.key: e.value,
  if (previous is String &&
      previous.isNotEmpty &&
      !timeTypeLabels.containsKey(previous))
    previous: 'Прежний тип · $previous',
};

List<Json> pauseSpans(Json session, {int? now}) {
  final result = <Json>[];
  int? opened;
  for (final event in rows(session['events'])) {
    final at = DateTime.tryParse(event['at']?.toString() ?? '')
        ?.millisecondsSinceEpoch;
    if (at == null) continue;
    if (['pause', 'leisure'].contains(event['action'])) opened ??= at;
    if (['resume', 'finish', 'cancel'].contains(event['action']) &&
        opened != null) {
      if (at > opened) result.add({'start': opened, 'end': at});
      opened = null;
    }
  }
  if (opened != null &&
      now != null &&
      session['status'] == 'paused' &&
      now > opened) {
    result.add({'start': opened, 'end': now});
  }
  return result;
}

int currentPauseMs(Json session, int now) {
  if (session['status'] != 'paused') return 0;
  final spans = pauseSpans(session, now: now);
  return spans.isEmpty ? 0 : max(0, now - (spans.last['start'] as int));
}

String pauseClock(Json session, int now) {
  final seconds = currentPauseMs(session, now) ~/ 1000;
  final h = seconds ~/ 3600;
  return '${h > 0 ? '$h:' : ''}${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

Map<String, Json> analyticsSessions(DashboardRepository repo) => {
  for (final s in [
    ...rows(repo.local.get('localHistory')),
    ...rows(repo.local.get('sharedLocalHistory')),
    ...rows(repo.cache('timer')['sessions']),
  ])
    if (s['id'] is String) s['id'].toString(): s,
};

List<Json> splitAnalyticsSpan(Json span, String kind, String id) {
  final result = <Json>[];
  final from = span['start'], end = span['end'];
  if (from is! int || end is! int || end <= from) return result;
  var start = from;
  while (start < end) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      start,
      isUtc: true,
    ).add(const Duration(hours: 5)).toIso8601String().substring(0, 10);
    final stop = min(
      end,
      DateTime.parse('${date}T00:00:00+05:00').millisecondsSinceEpoch +
          86400000,
    );
    result.add({
      'date': date,
      'durationSeconds': (stop - start) / 1000,
      'workType': kind,
      'timerSessionId': id,
    });
    start = stop;
  }
  return result;
}

/// Only explicit closed pauses/rest in completed, non-conflicting sessions.
/// Work intervals are counted separately; clock gaps are never inferred as waste.
Set<String> analyticsBlockedSessions(DashboardRepository repo) => {
  for (final q in repo.pending.where((q) => q['state'] == 'conflict'))
    (object(object(q['body'])['session'])['id'] ??
            object(object(q['body'])['input'])['sessionId'])
        .toString(),
};

List<Json> analyticsRestRows(DashboardRepository repo) {
  final blocked = analyticsBlockedSessions(repo);
  final result = <Json>[];
  for (final s in analyticsSessions(repo).values) {
    final id = s['id'].toString();
    if (s['status'] != 'finished' ||
        s['allocation'] == 'excluded' ||
        blocked.contains(id)) {
      continue;
    }
    final rest = rows(s['leisureIntervals']);
    if (['short_break', 'long_break'].contains(s['phase'])) {
      rest.addAll(rows(s['intervals']));
    }
    for (final span in rest) {
      result.addAll(splitAnalyticsSpan(span, 'leisure', id));
    }
    for (final span in pauseSpans(s)) {
      var pieces = [span];
      for (final r in rest) {
        final next = <Json>[];
        for (final piece in pieces) {
          final a = piece['start'] as int, b = piece['end'] as int;
          final x = r['start'] as int, y = r['end'] as int;
          if (y <= a || x >= b) {
            next.add(piece);
            continue;
          }
          if (a < x) next.add({'start': a, 'end': x});
          if (y < b) next.add({'start': y, 'end': b});
        }
        pieces = next;
      }
      for (final piece in pieces) {
        result.addAll(splitAnalyticsSpan(piece, 'unclassified', id));
      }
    }
  }
  return result;
}

List<Json> timeComposition(
  List<Json> entries,
  List<Json> facts,
  Map<String, Json> sessions,
) {
  final values = {
    for (final key in timeTypeLabels.keys)
      key: <String, dynamic>{'type': key, 'seconds': 0.0, 'pomodoros': 0},
  };
  final entryTypes = <String, Set<String>>{};
  for (final entry in entries) {
    final seconds =
        (entry['durationSeconds'] as num?)?.toDouble() ??
        (entry['amount'] as num? ?? 0) * 3600.0;
    if (!seconds.isFinite || seconds <= 0) continue;
    final kind = timeType(entry['workType']);
    values[kind]!['seconds'] += seconds;
    if (entry['timerSessionId'] is String) {
      entryTypes.putIfAbsent(entry['timerSessionId'], () => {}).add(kind);
    }
  }
  final seen = <String>{};
  for (final fact in facts) {
    final id = fact['sessionId'];
    if (id is! String || !seen.add(id)) continue;
    final session = sessions[id];
    final known = entryTypes[id];
    final kind = session != null
        ? timeType(session['workType'])
        : known?.length == 1
        ? known!.first
        : 'unclassified';
    values[kind]!['pomodoros']++;
  }
  final total = values.values.fold<double>(0, (n, r) => n + r['seconds']);
  final count = seen.length;
  return [
    for (final row in values.values)
      {
        ...row,
        'percent': total > 0 ? row['seconds'] * 100 / total : null,
        'pomodoroPercent': count > 0 ? row['pomodoros'] * 100 / count : null,
      },
  ];
}
