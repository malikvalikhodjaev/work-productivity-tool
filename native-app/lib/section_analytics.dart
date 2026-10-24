import 'dart:math';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'model_hierarchy.dart';
import 'repository.dart';

class AnalyticsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const AnalyticsSection({
    super.key,
    required this.title,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Divider(thickness: 1),
      ),
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 14),
      ...children,
    ],
  );
}

class GoalHierarchy extends StatelessWidget {
  final List<Json> goals;
  final void Function(Json) edit, measure, child;
  const GoalHierarchy({
    super.key,
    required this.goals,
    required this.edit,
    required this.measure,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => ExpansionTile(
    initiallyExpanded: true,
    title: const Text('Все цели · декомпозиция'),
    children: [
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'У каждой цели своя шкала. Проценты подцелей не складываются: прогресс родительской цели задаётся её собственным замером.',
        ),
      ),
      for (final goal in hierarchyRows(goals))
        Padding(
          padding: EdgeInsets.only(
            left: min((goal['_depth'] as int) * 18.0, 90),
          ),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${goal['_wbs']} · ${goal['title']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${goal['current'] ?? 'No Data'} → ${goal['target'] ?? 'No Data'} ${goal['unit'] ?? ''} · ${goal['status'] ?? ''}',
                  ),
                  if (goal['percent'] is num)
                    LinearProgressIndicator(
                      value: ((goal['percent'] as num) / 100)
                          .clamp(0, 1)
                          .toDouble(),
                    ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: () => edit(goal),
                        child: const Text('Настроить'),
                      ),
                      TextButton(
                        onPressed: () => measure(goal),
                        child: const Text('Замер'),
                      ),
                      TextButton(
                        onPressed: () => child(goal),
                        child: const Text('＋ Подцель'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

/// Confirmed time rows plus finished local sessions, once per timer session.
List<Json> analyticsTimeRows(DashboardRepository repo) {
  final entries = rows(repo.cache('entries')['entries'])
      .where((e) => e['metricId'] != 'alphas')
      .toList();
  final captured = entries
      .map((e) => e['timerSessionId'])
      .whereType<String>()
      .toSet();
  final sessions = <String, Json>{};
  for (final s in [
    ...rows(repo.cache('timer')['sessions']),
    ...rows(repo.local.get('sharedLocalHistory')),
    ...rows(repo.local.get('localHistory')),
  ]) {
    sessions[s['id'].toString()] = s;
  }
  for (final s in sessions.values.where(
    (s) =>
        s['status'] == 'finished' &&
        s['phase'] == 'work' &&
        s['allocation'] != 'excluded' &&
        !captured.contains(s['id']),
  )) {
    for (final interval in rows(s['intervals'])) {
      var start = interval['start'] as int;
      final end = interval['end'] as int;
      while (start < end) {
        final date = DateTime.fromMillisecondsSinceEpoch(
          start,
          isUtc: true,
        ).add(const Duration(hours: 5)).toIso8601String().substring(0, 10);
        final midnight =
            DateTime.parse('${date}T00:00:00+05:00').millisecondsSinceEpoch +
            86400000;
        final stop = min(end, midnight);
        entries.add({
          'date': date,
          'durationSeconds': (stop - start) / 1000,
          'timerSessionId': s['id'],
          'workType': s['workType'],
        });
        start = stop;
      }
    }
  }
  return entries;
}

class WorkAnalytics extends StatefulWidget {
  final DashboardRepository repo;
  const WorkAnalytics({super.key, required this.repo});
  @override
  State<WorkAnalytics> createState() => _WorkAnalyticsState();
}

class _WorkAnalyticsState extends State<WorkAnalytics> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final repo = widget.repo, week = selected ?? weekStart();
    final days = List.generate(
      7,
      (i) =>
          DateTime.parse('${week}T00:00:00Z')
              .add(Duration(days: i))
              .toIso8601String()
              .substring(0, 10),
    );
    final entries = analyticsTimeRows(repo)
        .where((e) => days.contains(e['date']))
        .toList();
    double hours(Iterable<Json> records) => records.fold<double>(
      0,
      (sum, e) =>
          sum +
          ((e['durationSeconds'] as num?) ??
                  (e['amount'] as num? ?? 0) * 3600) /
              3600,
    );
    final types = <String, List<Json>>{};
    for (final entry in entries) {
      types
          .putIfAbsent(
            (entry['workType'] ?? 'Не разобрано').toString(),
            () => [],
          )
          .add(entry);
    }
    final known = repo.cache('entries').isNotEmpty || entries.isNotEmpty;
    final normsKnown =
        repo.cache('dailyNorms').isNotEmpty || repo.pomodoroRows.isNotEmpty;
    return AnalyticsSection(
      title: 'Аналитика работы',
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Предыдущая неделя',
              onPressed: () => setState(
                () =>
                    selected = DateTime.parse(week)
                        .subtract(const Duration(days: 7))
                        .toIso8601String()
                        .substring(0, 10),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(weekRange(week)),
            IconButton(
              tooltip: 'Следующая неделя',
              onPressed: week.compareTo(weekStart()) >= 0
                  ? null
                  : () => setState(
                      () =>
                          selected = DateTime.parse(week)
                              .add(const Duration(days: 7))
                              .toIso8601String()
                              .substring(0, 10),
                    ),
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(
              onPressed: () => setState(() => selected = null),
              child: const Text('Эта неделя'),
            ),
          ],
        ),
        Text(
          'Учтено за неделю: ${known ? hours(entries).toStringAsFixed(1) : 'No Data'} ч',
          style: const TextStyle(fontSize: 20),
        ),
        const Text(
          'Завершённые сеансы и записи времени. Активный таймер сюда ещё не входит; повторы сеансов не суммируются.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Главная проблема выбранной недели',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        SelectableText(
          (repo.weeklyProblem(week)['text'] ?? 'No Data · не записана')
              .toString(),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            dataRowMinHeight: 64,
            dataRowMaxHeight: 180,
            columns: const [
              DataColumn(label: Text('День')),
              DataColumn(label: Text('Часы')),
              DataColumn(label: Text('Помидорки')),
              DataColumn(label: Text('План')),
              DataColumn(label: Text('Лимит')),
              DataColumn(label: Text('Проблема дня')),
            ],
            rows: [
              for (final day in days)
                DataRow(
                  color: WidgetStatePropertyAll(
                    repo.pomodoroCapacityForDate(day)['over'] == true
                        ? const Color(0xffffeeee)
                        : null,
                  ),
                  cells: [
                    DataCell(Text(day)),
                    DataCell(
                      Text(
                        known
                            ? hours(entries.where((e) => e['date'] == day))
                                  .toStringAsFixed(1)
                            : 'No Data',
                      ),
                    ),
                    DataCell(
                      Text(
                        normsKnown || repo.cache('timer').isNotEmpty
                            ? '${repo.pomodoroCapacityForDate(day)['actualPomodoros']}'
                            : 'No Data',
                      ),
                    ),
                    DataCell(
                      Text(
                        normsKnown
                            ? '${repo.pomodoroCapacityForDate(day)['planned']}'
                            : 'No Data',
                      ),
                    ),
                    DataCell(
                      Text(
                        '${repo.pomodoroCapacityForDate(day)['limit'] ?? 'No Data'}',
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 260,
                        child: SingleChildScrollView(
                          child: SelectableText(
                            (repo.entity(
                                      'problem:$day',
                                      rows(repo.cache('problems')['entries'])
                                              .where((e) => e['date'] == day)
                                              .firstOrNull ??
                                          {},
                                    )['text'] ??
                                    'No Data · не записана')
                                .toString(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Характер работ · ${types.isEmpty ? 'No Data' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        for (final type in types.entries)
          Text('${type.key}: ${hours(type.value).toStringAsFixed(1)} ч'),
        const Text(
          'Красный фон: план помидорок выше выбранного дневного лимита. Показаны данные, сохранённые на этом устройстве.',
        ),
      ],
    );
  }
}

class ModelAnalytics extends StatelessWidget {
  final DashboardRepository repo;
  final String? projectId;
  const ModelAnalytics({super.key, required this.repo, this.projectId});
  @override
  Widget build(BuildContext context) {
    final source = repo.cache('modelActivity');
    final stats = projectId == null
        ? source
        : rows(source['byProject'])
                  .where((p) => p['projectId'] == projectId)
                  .firstOrNull ??
              <String, dynamic>{};
    final activity = object(stats['activity']);
    final alphas = repo
        .entities('alphas', 'alpha')
        .where((a) => projectId == null || a['projectId'] == projectId)
        .toList();
    final adapted = alphas
        .where(
          (a) =>
              (a['uniqueName'] ?? '').toString().trim().isNotEmpty &&
              a['uniqueName'].toString().trim() !=
                  (a['typeName'] ?? '').toString().trim(),
        )
        .length;
    final known = repo.cache('portfolio').isNotEmpty || alphas.isNotEmpty;
    final lines = alphas.fold<int>(
      0,
      (sum, a) =>
          sum +
          ['description', 'criteria', 'evidence', 'nextStep'].fold<int>(
            0,
            (n, k) =>
                n +
                (a[k] ?? '')
                    .toString()
                    .split(RegExp(r'\r?\n'))
                    .where((s) => s.trim().isNotEmpty)
                    .length,
          ),
    );
    return AnalyticsSection(
      title: 'Аналитика моделирования',
      children: [
        Text(projectId == null ? 'Все проекты' : 'Выбранный проект'),
        Text(
          known
              ? 'Слотов: ${alphas.length} · с проектным именем: $adapted / ${alphas.length}'
              : 'Слоты: No Data',
        ),
        Text('Непустых строк в текущей модели: ${known ? lines : 'No Data'}'),
        Text('Неделя: ${source['week'] ?? 'No Data'} · по сохранённой истории'),
        for (final field in {
          'created': 'Создано строк',
          'edits': 'Сохранённых изменений',
          'renames': 'Изменений названий',
          'filled': 'Заполнений пустых текстовых полей',
          'addedLines': 'Добавлено непустых строк при сохранении',
        }.entries)
          Text(
            '${field.value}: ${source['recordedHistory'] == true ? activity[field.key] ?? 0 : 'No Data'}',
          ),
        const Text(
          'Счётчики описывают действия с моделью. Полезность изменений и состояние системы проверяются отдельно. Импорт и исходный снимок не входят в счётчики действий. Создание из шаблона входит в созданные строки.',
        ),
        if (repo.pending.any((p) => object(p['body'])['module'] == 'portfolio'))
          const Text(
            'Есть локальные правки модели: история обновится после синхронизации.',
          ),
      ],
    );
  }
}

int writingWords(Json entry) {
  final doc = object(entry['document']);
  if (doc['ops'] is! List) return entry['words'] as int? ?? 0;
  final text = rows(doc['ops'])
      .map((op) => op['insert'] is String ? op['insert'] : '')
      .join()
      .trim();
  return text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
}

List<Json> writingWeekRows(List<Json> entries, String week) =>
    List.generate(7, (i) {
      final day = DateTime.parse(week)
          .add(Duration(days: i))
          .toIso8601String()
          .substring(0, 10);
      final onDay = entries
          .where((e) => e['trashedAt'] == null && e['date'] == day)
          .toList();
      return {
        'date': day,
        'entries': onDay.length,
        'words': onDay.fold<int>(0, (sum, e) => sum + writingWords(e)),
        'favorite': onDay.where((e) => e['favorite'] == true).length,
      };
    });

class WritingAnalytics extends StatefulWidget {
  final DashboardRepository repo;
  const WritingAnalytics({super.key, required this.repo});
  @override
  State<WritingAnalytics> createState() => _WritingAnalyticsState();
}

class _WritingAnalyticsState extends State<WritingAnalytics> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final entries = repo.writingEntries
        .where((e) => e['trashedAt'] == null)
        .toList();
    final known = repo.cache('writing').isNotEmpty || entries.isNotEmpty;
    final week = selected ?? weekStart();
    final days = writingWeekRows(entries, week);
    final count = days.fold<int>(0, (sum, e) => sum + (e['entries'] as int));
    final words = days.fold<int>(0, (sum, e) => sum + (e['words'] as int));
    final maximum = days.fold<int>(1, (m, e) => max(m, e['entries'] as int));
    return AnalyticsSection(
      title: 'Аналитика письма',
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Предыдущая неделя',
              onPressed: () => setState(
                () =>
                    selected = DateTime.parse(week)
                        .subtract(const Duration(days: 7))
                        .toIso8601String()
                        .substring(0, 10),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(weekRange(week)),
            IconButton(
              tooltip: 'Следующая неделя',
              onPressed: week.compareTo(weekStart()) >= 0
                  ? null
                  : () => setState(
                      () =>
                          selected = DateTime.parse(week)
                              .add(const Duration(days: 7))
                              .toIso8601String()
                              .substring(0, 10),
                    ),
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(
              onPressed: () => setState(() => selected = null),
              child: const Text('Эта неделя'),
            ),
          ],
        ),
        Text(
          known ? 'За неделю: $count записей · $words слов' : 'No Data',
          style: const TextStyle(fontSize: 20),
        ),
        const Text(
          'По выбранной дате записи. Слова — объём текущих сохранённых текстов на эти даты, а не количество набранных за период слов. Корзина исключена.',
        ),
        if (known)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('День')),
                DataColumn(label: Text('Записи')),
                DataColumn(label: Text('Объём · слова')),
                DataColumn(label: Text('Избранные')),
                DataColumn(label: Text('Ритм · записи')),
              ],
              rows: [
                for (final day in days)
                  DataRow(
                    cells: [
                      DataCell(Text(day['date'].toString())),
                      DataCell(Text('${day['entries']}')),
                      DataCell(Text('${day['words']}')),
                      DataCell(Text('${day['favorite']}')),
                      DataCell(
                        SizedBox(
                          width: 100,
                          child: LinearProgressIndicator(
                            value: (day['entries'] as int) / maximum,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text(
          known
              ? 'В архиве: ${entries.length} записей · ${entries.fold<int>(0, (sum, e) => sum + writingWords(e))} слов · ${entries.where((e) => e['favorite'] == true).length} избранных'
              : 'Архив: No Data',
        ),
      ],
    );
  }
}
