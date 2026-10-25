import 'package:flutter/material.dart';

import 'domain.dart';
import 'repository.dart';

/// A read-only projection: queued measurements are visible without rewriting
/// the archive, the scale, or any earlier measurement.
List<Json> goalMeasurements(DashboardRepository repo, Json goal) {
  final kind = goal['characteristicId'] == null ? 'goal' : 'characteristic';
  final id = goal['characteristicId'] ?? goal['id'];
  final result = <Json>[
    for (final m in rows(repo.cache('workspace')['measurements']))
      if (m['kind'] == kind && m['targetId'] == id) {...m},
    for (final q in repo.pending)
      if (q['state'] != 'conflict' &&
          object(q['body'])['module'] == 'workspace' &&
          object(q['body'])['action'] == 'measure' &&
          object(object(q['body'])['input'])['kind'] == kind &&
          object(object(q['body'])['input'])['targetId'] == id)
        {
          ...object(object(q['body'])['input']),
          'id': q['id'],
          'pending': true,
          'createdAt': DateTime.fromMillisecondsSinceEpoch(
            q['created'] as int,
            isUtc: true,
          ).toIso8601String(),
        },
  ];
  // Keep insertion order as a tie-breaker, matching the server's latest rule.
  final order = {for (var i = 0; i < result.length; i++) result[i]: i};
  result.sort((a, b) {
    final day = '${b['date']}'.compareTo('${a['date']}');
    if (day != 0) return day;
    final stamp = '${b['createdAt']}'.compareTo('${a['createdAt']}');
    return stamp != 0 ? stamp : order[b]!.compareTo(order[a]!);
  });
  return result;
}

Json evaluateGoal(Json goal, List<Json> history) {
  num? value(dynamic raw) => raw is num && raw.isFinite ? raw : null;
  final latest = history.firstOrNull ?? object(goal['measurement']);
  final current = value(latest['value'] ?? goal['current']);
  final baseline = value(goal['baseline']), target = value(goal['target']);
  final delta = current != null && baseline != null ? current - baseline : null;
  final previous = history.length > 1 ? value(history[1]['value']) : null;
  final ratio =
      current != null &&
          baseline != null &&
          target != null &&
          target != baseline
      ? (current - baseline) / (target - baseline)
      : null;
  return {
    ...goal,
    'current': current,
    'measurement': latest,
    'history': history,
    'delta': delta,
    'lastChange': current != null && previous != null
        ? current - previous
        : null,
    'percent': ratio == null ? null : (ratio * 100).clamp(0, 100).round(),
    'reached': current == null || target == null
        ? null
        : goal['direction'] == 'down'
        ? current <= target
        : current >= target,
  };
}

List<Json> projectedGoals(DashboardRepository repo) => [
  for (final goal in repo.entities('goals', 'goal'))
    evaluateGoal(goal, goalMeasurements(repo, goal)),
];

String goalNumber(dynamic value) {
  if (value is! num || !value.isFinite) return 'No Data';
  return (value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toString())
      .replaceAll('.', ',');
}

class GoalProgressSummary extends StatelessWidget {
  final Json goal;
  final String? heading;
  const GoalProgressSummary({super.key, required this.goal, this.heading});
  @override
  Widget build(BuildContext context) {
    final delta = goal['delta'];
    String signed(num n) => '${n > 0 ? '+' : ''}${goalNumber(n)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          heading ?? goal['title'].toString(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            for (final e in {
              'Было': goal['baseline'],
              'Сейчас': goal['current'],
              'Хочу': goal['target'],
            }.entries)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.key, style: const TextStyle(color: Color(0xff727780))),
                  Text(
                    goalNumber(e.value),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          (goal['unit'] ?? '').toString().isEmpty
              ? 'Единица и период пока не заданы'
              : goal['unit'].toString(),
        ),
        Text(
          delta is num
              ? 'Изменение от начала: ${signed(delta)}'
              : 'Изменение от начала: No Data',
        ),
        if (goal['lastChange'] is num)
          Text('К прошлому замеру: ${signed(goal['lastChange'])}'),
        const SizedBox(height: 10),
        if (goal['percent'] is num) ...[
          LinearProgressIndicator(value: (goal['percent'] as num) / 100),
          Text(
            'Продвижение к ориентиру: ${goal['percent']}%${goal['reached'] == true ? ' · достигнут' : ''}',
          ),
        ] else
          const Text(
            'Прогресс: No Data · нужны исходное значение, новый замер и отличающийся ориентир',
          ),
        const SizedBox(height: 8),
        Text(
          'Последний замер: ${object(goal['measurement'])['date'] ?? 'No Data'}${object(goal['measurement'])['pending'] == true ? ' · сохранён на устройстве' : ''}',
          style: const TextStyle(fontSize: 12, color: Color(0xff727780)),
        ),
      ],
    );
  }
}

Future<void> showGoalHistory(
  BuildContext context,
  Json goal,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('Замеры · ${goal['title']}'),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rows(goal['history']).isEmpty)
              const Text('No Data · замеров пока нет'),
            for (final m in rows(goal['history'])) ...[
              Text(
                '${m['date']} · ${goalNumber(m['value'])} ${goal['unit'] ?? ''}${m['pending'] == true ? ' · на устройстве' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if ((m['evidence'] ?? '').toString().isNotEmpty)
                SelectableText(m['evidence'].toString()),
              const Divider(),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Закрыть'),
      ),
    ],
  ),
);
