import 'package:flutter/material.dart';

import 'domain.dart';
import 'pomodoro_plan.dart';
import 'repository.dart';
import 'section_analytics.dart';
import 'workspace_table.dart';
import 'table_progress.dart';

/// Sum exactly the owner's effective daily rules, never the metric templates.
List<Json> userNormsWeek(DashboardRepository repo, String week) {
  final start = pomodoroMonday(week);
  final days = [for (var i = 0; i < 7; i++) pomodoroShift(start, i)];
  final groups = <String, Json>{};
  for (final day in days) {
    for (final norm in repo.pomodoroTargetsForDate(day)) {
      final key = norm['workRef'].toString();
      final row = groups.putIfAbsent(
        key,
        () => {
          'id': key,
          'title': norm['title'],
          'planned': 0,
          'actual': 0,
          'pending': 0,
        },
      );
      row['title'] = norm['title'];
      row['planned'] = (row['planned'] as int) + (norm['target'] as int);
      row['actual'] = (row['actual'] as int) + (norm['actualPomodoros'] as int);
      row['pending'] =
          (row['pending'] as int) + (norm['pendingPomodoros'] as int);
    }
  }
  final entries = analyticsTimeRows(repo);
  final known = repo.cache('entries').isNotEmpty || entries.isNotEmpty;
  for (final row in groups.values) {
    final records = entries.where(
      (e) => e['workRef'] == row['id'] && days.contains(e['date']),
    );
    row['hours'] = known
        ? records.fold<double>(
            0,
            (sum, e) =>
                sum +
                ((e['durationSeconds'] as num?) ??
                        (e['amount'] as num? ?? 0) * 3600) /
                    3600,
          )
        : null;
  }
  return groups.values.toList();
}

class NormsOverview extends StatefulWidget {
  final DashboardRepository repo;
  const NormsOverview({super.key, required this.repo});
  @override
  State<NormsOverview> createState() => _NormsOverviewState();
}

class _NormsOverviewState extends State<NormsOverview> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final week = selected ?? pomodoroMonday(pomodoroDate(widget.repo.now));
    final items = userNormsWeek(widget.repo, week);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Предыдущая неделя нормативов',
              onPressed: () =>
                  setState(() => selected = pomodoroShift(week, -7)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                'Сумма дневных нормативов · $week — ${pomodoroShift(week, 6)}',
              ),
            ),
            IconButton(
              tooltip: 'Следующая неделя нормативов',
              onPressed: () =>
                  setState(() => selected = pomodoroShift(week, 7)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'На этой неделе своих нормативов нет. Добавленные в дневном чек-листе нормативы появятся здесь.',
            ),
          ),
        if (items.isNotEmpty)
          WorkspaceTable(
            repo: widget.repo,
            viewKey: 'userNormsWeek:${widget.repo.serverId}',
            grouping: false,
            compactToolbar: true,
            items: items,
            columns: const [
              WorkColumn('title', 'Работа', width: 340),
              WorkColumn('planned', 'План за неделю · помидорки', width: 220),
              WorkColumn('actual', 'Выполнение · помидорки', width: 240),
              WorkColumn('hours', 'Учтено · часы', width: 180),
            ],
            value: (r, id) => id == '*' ? r['title'] : r[id],
            cell: (_, r, c) => c.id == 'actual'
                ? TableProgress(
                    key: ValueKey('norm-week-progress:${r['id']}'),
                    done: r['actual'] as num,
                    planned: r['planned'] as num,
                    pending: (r['pending'] as int) > 0
                        ? 'На устройстве: ${r['pending']}'
                        : null,
                  )
                : Text(
                    c.id == 'hours'
                        ? (r['hours'] == null
                              ? 'Не загружено'
                              : (r['hours'] as num)
                                    .toStringAsFixed(2)
                                    .replaceAll('.', ','))
                        : c.id == 'actual'
                        ? '${r['actual']}${(r['pending'] as int) > 0 ? ' · на устройстве: ${r['pending']}' : ''}'
                        : '${r[c.id]}',
                  ),
          ),
      ],
    );
  }
}
