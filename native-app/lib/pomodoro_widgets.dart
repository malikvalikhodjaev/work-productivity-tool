import 'package:flutter/material.dart';

import 'domain.dart';
import 'forms.dart';
import 'pomodoro_plan.dart';
import 'repository.dart';

Future<bool> editPomodoroTarget(
  BuildContext context,
  DashboardRepository repo, {
  Json? previous,
  String? ref,
  String? title,
}) async {
  final entities = rows(repo.cache('workspace')['entities']);
  if (entities.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Сначала создай работу или кейс'),
        content: const Text(
          'В разделе «Работа» добавь карточку. Норматив будет учитывать помидорки её таймера.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
    return false;
  }
  final baseRecords = rows(repo.cache('dailyNorms')['pomodoroTargets'])
      .map((n) => Map<String, dynamic>.from(n))
      .toList();
  return editFields(
    context,
    title: 'Ежедневный норматив помидорок',
    initial: {
      'date': previous?['date'] ?? today(),
      'workRef': previous?['workRef'] ?? ref ?? entities.first['ref'],
      'title': previous?['title'] ?? title ?? '',
      'target': previous?['target'] ?? 1,
    },
    fields: [
      const FieldSpec('date', 'Действует с · YYYY-MM-DD'),
      FieldSpec(
        'workRef',
        'Работа / задача / кейс',
        options: {
          for (final e in entities) e['ref'].toString(): e['title'].toString(),
        },
      ),
      const FieldSpec('title', 'Название норматива'),
      const FieldSpec(
        'target',
        'Помидорок за день · пусто для снятия',
        integer: true,
      ),
    ],
    save: (input) async {
      final date = input['date'].toString(),
          parsed = DateTime.tryParse('${input['date']}T12:00:00Z');
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          parsed == null ||
          parsed.toIso8601String().substring(0, 10) != date) {
        throw ArgumentError('Дата: YYYY-MM-DD.');
      }
      if (input['title'].toString().trim().isEmpty ||
          input['title'].toString().length > 240) {
        throw ArgumentError('Впиши название до 240 знаков.');
      }
      final target = input['target'] as int?;
      if (target != null && (target < 1 || target > 1440)) {
        throw ArgumentError('Норма: целое число от 1 до 1440.');
      }
      final old = baseRecords
          .where((n) => n['date'] == date && n['workRef'] == input['workRef'])
          .firstOrNull;
      repo.nativeSave(
        'pomodoroTarget',
        'save',
        input,
        'pomodoro:$date:${input['workRef']}',
        expectedUpdatedAt: old?['updatedAt'],
      );
      repo.local.set(
        'pomodoroReminder:$date',
        DateTime.now().millisecondsSinceEpoch + 3600000,
      );
    },
  );
}

class PomodoroChecklist extends StatelessWidget {
  final DashboardRepository repo;
  final bool compact;
  final Future<void> Function(String ref, String title)? focus;
  const PomodoroChecklist({
    super.key,
    required this.repo,
    this.compact = false,
    this.focus,
  });
  @override
  Widget build(BuildContext context) {
    final norms = repo.pomodoroTargetsForDate();
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Помидорки на сегодня',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: () => editPomodoroTarget(context, repo),
                    icon: const Icon(Icons.add),
                    tooltip: 'Норматив на день',
                  ),
                ],
              ),
              if (norms.isEmpty) const Text('Нормативы на сегодня не заданы.'),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: compact ? 180 : 280),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final n in norms)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Icon(
                                n['actualPomodoros'] >= n['target']
                                    ? Icons.check_box_outlined
                                    : Icons.check_box_outline_blank,
                                size: 19,
                                color: n['actualPomodoros'] >= n['target']
                                    ? const Color(0xff347558)
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 9),
                              Expanded(child: Text(n['title'].toString())),
                              Text(
                                '${n['actualPomodoros']}/${n['target']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (focus != null)
                                IconButton(
                                  tooltip: 'Фокус',
                                  onPressed: () => focus!(
                                    n['workRef'].toString(),
                                    n['title'].toString(),
                                  ),
                                  icon: const Icon(Icons.play_arrow_outlined),
                                ),
                              IconButton(
                                tooltip: 'Изменить норматив',
                                onPressed: () => editPomodoroTarget(
                                  context,
                                  repo,
                                  previous: n,
                                ),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (norms.any((n) => (n['pendingPomodoros'] as int) > 0))
                const Text(
                  'Есть помидорки, ожидающие синхронизации.',
                  style: TextStyle(fontSize: 12),
                ),
              if (!compact)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Считаются учтённые полные рабочие помидорки.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PomodoroWeek extends StatelessWidget {
  final DashboardRepository repo;
  const PomodoroWeek({super.key, required this.repo});
  @override
  Widget build(BuildContext context) {
    final week = pomodoroMonday(today()),
        groups = pomodoroWeekRows(
          repo.pomodoroRows,
          repo.pomodoroFacts,
          pomodoroMonday(today()),
        );
    final days = List.generate(7, (i) => pomodoroShift(week, i));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Помидорки за неделю',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            Text('$week — ${days.last}'),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('No Data — на эту неделю нормы ещё не заданы.'),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  horizontalMargin: 0,
                  columnSpacing: 20,
                  columns: [
                    const DataColumn(label: Text('Норматив')),
                    for (final d in days)
                      DataColumn(
                        label: Text('${d.substring(8)}.${d.substring(5, 7)}'),
                      ),
                    const DataColumn(label: Text('Неделя')),
                  ],
                  rows: [
                    for (final row in groups)
                      DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 180,
                              child: Text(row['title'].toString()),
                            ),
                          ),
                          for (final d in days)
                            DataCell(
                              Text(() {
                                final n = rows(row['days'])
                                    .where((n) => n['date'] == d)
                                    .firstOrNull;
                                return n == null
                                    ? '—'
                                    : '${n['actualPomodoros']}/${n['target']}';
                              }()),
                            ),
                          DataCell(
                            Text('${row['actualPomodoros']}/${row['target']}'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
