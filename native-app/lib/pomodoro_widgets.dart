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
  return await showDialog<bool>(
        context: context,
        builder: (_) => _PomodoroTargetEditor(
          repo: repo,
          previous: previous,
          ref: ref,
          title: title,
        ),
      ) ??
      false;
}

List<Json> _normWorks(DashboardRepository repo) {
  final entities = {
    for (final e in rows(repo.cache('workspace')['entities']))
      e['ref'].toString(): e,
  };
  for (final collection in {
    'workItems': 'work',
    'cases': 'case',
    'tasks': 'task',
  }.entries) {
    for (final e in repo.entities(collection.key, collection.value)) {
      final ref = '${collection.value}:${e['id']}';
      entities[ref] = {...e, 'ref': ref};
    }
  }
  return entities.values.toList();
}

class _PomodoroTargetEditor extends StatefulWidget {
  final DashboardRepository repo;
  final Json? previous;
  final String? ref, title;
  const _PomodoroTargetEditor({
    required this.repo,
    this.previous,
    this.ref,
    this.title,
  });
  @override
  State<_PomodoroTargetEditor> createState() => _PomodoroTargetEditorState();
}

class _PomodoroTargetEditorState extends State<_PomodoroTargetEditor> {
  late final TextEditingController date, title, target;
  late final List<Json> baseRecords;
  String? workRef, error;
  bool saving = false, creating = false;

  DashboardRepository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    final entities = _normWorks(repo);
    workRef = widget.previous?['workRef'] ?? widget.ref;
    date = TextEditingController(text: widget.previous?['date'] ?? today());
    title = TextEditingController(
      text:
          widget.previous?['title'] ??
          widget.title ??
          entities.where((e) => e['ref'] == workRef).firstOrNull?['title'] ??
          '',
    );
    target = TextEditingController(
      text: (widget.previous?['target'] ?? 1).toString(),
    );
    baseRecords = rows(repo.cache('dailyNorms')['pomodoroTargets'])
        .map((n) => Map<String, dynamic>.from(n))
        .toList();
    repo.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    repo.removeListener(refresh);
    date.dispose();
    title.dispose();
    target.dispose();
    super.dispose();
  }

  Future<void> createWork() async {
    setState(() => creating = true);
    Json? created;
    try {
      await editFields(
        context,
        title: repo.timerOnly ? 'Создать работу' : 'Создать работу / кейс',
        initial: {'kind': 'work', 'title': '', 'description': ''},
        fields: [
          if (!repo.timerOnly)
            const FieldSpec(
              'kind',
              'Тип',
              options: {'work': 'Работа', 'case': 'Кейс'},
            ),
          const FieldSpec('title', 'Название'),
          const FieldSpec('description', 'Описание и размышления', lines: 4),
        ],
        save: (input) async {
          final isCase = input['kind'] == 'case';
          final name = input['title'].toString(),
              note = input['description'].toString();
          final maxTitle = isCase ? 200 : 300, maxNote = isCase ? 4000 : 12000;
          if (name.trim().isEmpty || name.length > maxTitle) {
            throw ArgumentError('Название: от 1 до $maxTitle знаков.');
          }
          if (note.length > maxNote) {
            throw ArgumentError('Описание: до $maxNote знаков.');
          }
          final id = uuid.v4(), ref = '${isCase ? 'case' : 'work'}:$id';
          repo.nativeSave(
            'workspace',
            isCase ? 'saveCase' : 'saveWorkItem',
            isCase
                ? {
                    'clientId': id,
                    'title': name,
                    'context': note,
                    'status': 'new',
                  }
                : {
                    'id': id,
                    'create': true,
                    'expectedRevision': 0,
                    'requestId': uuid.v4(),
                    'title': name,
                    'kind': 'work',
                    'stage': 'planned',
                    'description': note,
                    'allocation': 'unclassified',
                  },
            ref,
          );
          created = {'ref': ref, 'title': name};
        },
      );
      if (mounted && created != null) {
        setState(() {
          workRef = created!['ref'];
          title.text = created!['title'];
          error = null;
        });
      }
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final input = <String, dynamic>{
        'date': date.text,
        'workRef': workRef,
        'title': title.text,
        'target': target.text.isEmpty ? null : int.tryParse(target.text),
        if (widget.previous == null) 'create': true,
      };
      if (workRef == null ||
          !_normWorks(repo).any((e) => e['ref'] == workRef)) {
        throw ArgumentError('Выбери или создай работу / кейс.');
      }
      if (target.text.isNotEmpty && input['target'] == null) {
        throw ArgumentError('Норма: целое число от 1 до 1440.');
      }
      _savePomodoroTarget(repo, input, baseRecords);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entities = _normWorks(repo);
    final selected = entities.any((e) => e['ref'] == workRef) ? workRef : null;
    return PopScope(
      canPop: !saving && !creating,
      child: AlertDialog(
        title: Text(
          widget.previous == null
              ? 'Добавить ежедневный норматив'
              : 'Изменить ежедневный норматив',
        ),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: date,
                  decoration: const InputDecoration(
                    labelText: 'Действует с · YYYY-MM-DD',
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: ValueKey(selected),
                  initialValue: selected,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: repo.timerOnly
                        ? 'Работа'
                        : 'Работа / задача / кейс',
                  ),
                  hint: Text(
                    entities.isEmpty
                        ? 'Создай работу или кейс'
                        : 'Выбери работу',
                  ),
                  items: [
                    for (final e in entities)
                      DropdownMenuItem(
                        value: e['ref'].toString(),
                        child: Text(e['title'].toString()),
                      ),
                  ],
                  onChanged: saving || creating || widget.previous != null
                      ? null
                      : (ref) => setState(() {
                          workRef = ref;
                          title.text =
                              entities
                                  .where((e) => e['ref'] == ref)
                                  .firstOrNull?['title'] ??
                              '';
                        }),
                ),
                if (widget.previous == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: saving || creating ? null : createWork,
                      icon: const Icon(Icons.add),
                      label: Text(
                        repo.timerOnly
                            ? 'Создать работу'
                            : 'Создать работу / кейс',
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Каждая строка чек-листа относится к своей работе. Для отдельного счётчика выбери другую карточку или создай новую.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(
                    labelText: 'Название норматива',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: target,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Помидорок за день · пусто для снятия',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ежедневно, без срока окончания — пока не изменишь или не снимешь.',
                  style: TextStyle(fontSize: 12),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving || creating
                ? null
                : () => Navigator.pop(context, false),
            child: const Text('Закрыть'),
          ),
          FilledButton(
            onPressed: saving || creating ? null : save,
            child: Text(saving ? 'Сохраняю…' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

void _savePomodoroTarget(
  DashboardRepository repo,
  Json input,
  List<Json> baseRecords,
) {
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
  if (input['create'] == true &&
      repo
          .pomodoroTargetsForDate(date)
          .any((n) => n['workRef'] == input['workRef'])) {
    throw ArgumentError(
      'Для этой работы уже есть норматив. Измени его через карандаш или создай другую работу для нового норматива.',
    );
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
