import 'domain.dart';

/// Project an immutable queued command using its recorded time, never sync time.
Json projectTimer(Json before, String action, Json input, int at) {
  final snapshot = <String, dynamic>{...before};
  final sessions = rows(before['sessions']);
  Json? active = before['active'] is Map ? object(before['active']) : null;
  var cycle = before['cycleCount'] as int? ?? 0;
  if (['start', 'startBreak'].contains(action)) {
    if (active != null) throw StateError('Сначала заверши текущий сеанс.');
    final settings = object(
      input['settings'] ?? before['settings'] ?? timerDefaults,
    );
    final phase = action == 'start'
        ? 'work'
        : cycle >= settings['longBreakEvery']
        ? 'long_break'
        : 'short_break';
    active = newLocalSession(
      title: phase == 'work'
          ? input['title'].toString()
          : phase == 'long_break'
          ? 'Длинный перерыв'
          : 'Короткий перерыв',
      workRef: input['workRef'] as String?,
      metricId: input['metricId'] as String?,
      allocation: (input['allocation'] ?? 'unclassified').toString(),
      workType: (input['workType'] ?? '').toString(),
      mode: phase == 'work' ? input['mode'].toString() : 'pomodoro',
      phase: phase,
      settings: settings,
      now: at,
    );
    active['id'] = input['newSessionId'];
  } else {
    if (active == null || active['id'] != input['sessionId']) {
      throw StateError('Открой нужный сеанс таймера.');
    }
    active = changeLocalSession(
      active,
      action,
      at,
      observation: (input['observation'] ?? '').toString(),
      workedSeconds: input['workedSeconds'] as int?,
      leisureUntil: input['leisureUntil'] as int?,
    );
    if (action == 'finish') {
      cycle += active['completedPomodoros'] as int? ?? 0;
      if (active['phase'] == 'long_break') cycle = 0;
    }
  }
  final changed = active;
  final index = sessions.indexWhere((s) => s['id'] == changed['id']);
  if (index < 0) {
    sessions.add(changed);
  } else {
    sessions[index] = changed;
  }
  snapshot.addAll({
    'offlineCommands': true,
    'revision': (before['revision'] as int? ?? 0) + 1,
    'cycleCount': cycle,
    'sessions': sessions,
    'active': ['finished', 'cancelled'].contains(changed['status'])
        ? null
        : changed,
  });
  return snapshot;
}
