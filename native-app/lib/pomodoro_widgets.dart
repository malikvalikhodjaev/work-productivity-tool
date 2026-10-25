import 'package:flutter/material.dart';

import 'domain.dart';
import 'forms.dart';
import 'pomodoro_plan.dart';
import 'repository.dart';
import 'time_composition.dart';

Future<void> editPomodoroCapacity(
  BuildContext context,
  DashboardRepository repo,
) async {
  final day = today(),
      records = rows(repo.cache('dailyNorms')['pomodoroCapacities']);
  await editFields(
    context,
    title: 'Дневной лимит по силам',
    initial: {
      'date': day,
      'limit': pomodoroCapacityOn(repo.pomodoroCapacityRows, day),
    },
    fields: const [
      FieldSpec('date', 'Действует с · YYYY-MM-DD'),
      FieldSpec(
        'limit',
        'Максимум помидорок в день · пусто для снятия',
        integer: true,
      ),
    ],
    save: (input) async {
      validatePomodoroCapacity(input);
      final previous = records
          .where((r) => r['date'] == input['date'])
          .firstOrNull;
      repo.nativeSave(
        'pomodoroCapacity',
        'save',
        input,
        'capacity:${input['date']}',
        expectedUpdatedAt: previous?['updatedAt'],
      );
    },
  );
}

class PomodoroCapacityNotice extends StatelessWidget {
  final Json summary;
  final int workMinutes;
  const PomodoroCapacityNotice({
    super.key,
    required this.summary,
    this.workMinutes = 25,
  });
  @override
  Widget build(BuildContext context) {
    final actual = summary['actualPomodoros'] as int?;
    final limit = summary['limit'] as int?;
    final over =
        summary['over'] == true ||
        (actual != null && limit != null && actual > limit);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xfff3f4f4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffdde1df)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (actual != null) ...[
            if (limit != null)
              PomodoroCapacityProgress(
                actual: actual,
                limit: limit,
                workMinutes: workMinutes,
              )
            else
              Text('Сделано: $actual · дневной лимит не задан'),
            const SizedBox(height: 8),
          ],
          Text(
            '${!over && limit != null ? 'Всё в пределах лимита. ' : ''}${summary['message']}',
            style: TextStyle(
              fontSize: 12,
              color: over ? const Color(0xffb3261e) : const Color(0xff347558),
            ),
          ),
        ],
      ),
    );
  }
}

class PomodoroCapacityProgress extends StatelessWidget {
  final int actual, limit;
  final int workMinutes;
  const PomodoroCapacityProgress({
    super.key,
    required this.actual,
    required this.limit,
    this.workMinutes = 25,
  });

  @override
  Widget build(BuildContext context) {
    final within = actual.clamp(0, limit).toInt();
    final excess = actual > limit ? actual - limit : 0;
    final remaining = actual < limit ? limit - actual : 0;
    final percent = (actual * 100 / limit).round();
    String hours(int count) =>
        '${(count * workMinutes / 60).toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '').replaceAll('.', ',')} ч';
    return Semantics(
      label: 'Помидорки за день',
      value:
          '$actual из $limit, $percent процентов'
          '${excess > 0 ? ', сверх лимита $excess, ${hours(excess)}' : ', до лимита $remaining, ${hours(remaining)}'}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Сделано $actual / $limit · $percent%',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 9,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (within > 0)
                      Expanded(
                        flex: within,
                        child: const ColoredBox(color: Color(0xff347558)),
                      ),
                    if (excess > 0) ...[
                      const SizedBox(width: 2),
                      Expanded(
                        flex: excess,
                        child: const ColoredBox(color: Color(0xffb3261e)),
                      ),
                    ],
                    if (remaining > 0)
                      Expanded(
                        flex: remaining,
                        child: const ColoredBox(color: Color(0xffdce5df)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              excess > 0
                  ? '+$excess сверх лимита (${hours(excess)})'
                  : remaining == 0
                  ? 'Дневной лимит достигнут'
                  : 'До лимита: $remaining (${hours(remaining)})',
              style: TextStyle(
                fontSize: 12,
                color: excess > 0 ? const Color(0xffb3261e) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  String workType = '';
  bool saving = false, creating = false;

  DashboardRepository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    final entities = _normWorks(repo);
    workRef = widget.previous?['workRef'] ?? widget.ref;
    workType = widget.previous?['workType']?.toString() ?? '';
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
    date.addListener(refresh);
    target.addListener(refresh);
    repo.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    repo.removeListener(refresh);
    date.removeListener(refresh);
    target.removeListener(refresh);
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
        'workType': workType,
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
                DropdownButtonFormField<String>(
                  key: const ValueKey('norm-time-type'),
                  initialValue: workType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Тип времени норматива',
                  ),
                  items:
                      {
                            '': 'Как у карточки работы',
                            ...(timeTypeOptions(workType)..remove('')),
                          }.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setState(() => workType = value ?? ''),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Тип применяется к новым сеансам этой работы. Уже учтённое время не меняется.',
                  style: TextStyle(fontSize: 12),
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
                if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date.text) &&
                    (target.text.isEmpty ||
                        (int.tryParse(target.text) ?? 0) > 0))
                  PomodoroCapacityNotice(
                    workMinutes: repo.settings['workMinutes'] as int,
                    summary: pomodoroCapacitySummary(
                      repo.pomodoroTargetsForDate(date.text),
                      repo.pomodoroCapacityRows,
                      date.text,
                      candidate: workRef == null
                          ? null
                          : {
                              'workRef': workRef,
                              'target': int.tryParse(target.text),
                            },
                    ),
                  ),
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
  final bool rowsFirst;
  final bool scrollChecks;
  final Future<void> Function(String ref, String title)? focus;
  const PomodoroChecklist({
    super.key,
    required this.repo,
    this.compact = false,
    this.rowsFirst = false,
    this.scrollChecks = true,
    this.focus,
  });
  @override
  Widget build(BuildContext context) {
    final norms = repo.pomodoroTargetsForDate();
    final denseButtons = rowsFirst && compact;
    final buttonConstraints = denseButtons
        ? const BoxConstraints(minWidth: 48, minHeight: 48)
        : null;
    final buttonDensity = denseButtons
        ? VisualDensity.standard
        : VisualDensity.standard;
    final buttonStyle = denseButtons
        ? IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            fixedSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
            padding: const EdgeInsets.all(4),
          )
        : null;
    Widget normRow(Json n) => LayoutBuilder(
      builder: (context, box) {
        final stacked =
            box.maxWidth / (MediaQuery.textScalerOf(context).scale(14) / 14) <
            360;
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (focus != null)
              IconButton(
                tooltip: 'Фокус',
                style: buttonStyle,
                constraints: buttonConstraints,
                padding: denseButtons ? const EdgeInsets.all(4) : null,
                visualDensity: buttonDensity,
                onPressed: () =>
                    focus!(n['workRef'].toString(), n['title'].toString()),
                icon: const Icon(Icons.play_arrow_outlined),
              ),
            IconButton(
              tooltip: 'Изменить норматив',
              style: buttonStyle,
              constraints: buttonConstraints,
              padding: denseButtons ? const EdgeInsets.all(4) : null,
              visualDensity: buttonDensity,
              onPressed: () => editPomodoroTarget(context, repo, previous: n),
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          ],
        );
        final line = Row(
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n['title'].toString(),
                    key: ValueKey('pomodoro-title:${n['workRef']}'),
                  ),
                  if ((n['workType'] ?? '').toString().isNotEmpty)
                    Text(
                      timeTypeLabels[timeType(n['workType'])]!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xff53645b),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${n['actualPomodoros']}/${n['target']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (!stacked) controls,
          ],
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    line,
                    Align(alignment: Alignment.centerRight, child: controls),
                  ],
                )
              : line,
        );
      },
    );
    final checks = Column(children: [for (final n in norms) normRow(n)]);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(
          rowsFirst
              ? 8
              : compact
              ? 14
              : 18,
        ),
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
                    onPressed: () => editPomodoroCapacity(context, repo),
                    style: buttonStyle,
                    constraints: buttonConstraints,
                    padding: denseButtons ? const EdgeInsets.all(4) : null,
                    visualDensity: buttonDensity,
                    icon: const Icon(Icons.speed_outlined),
                    tooltip: 'Дневной лимит по силам',
                  ),
                  IconButton(
                    onPressed: () => editPomodoroTarget(context, repo),
                    style: buttonStyle,
                    constraints: buttonConstraints,
                    padding: denseButtons ? const EdgeInsets.all(4) : null,
                    visualDensity: buttonDensity,
                    icon: const Icon(Icons.add),
                    tooltip: 'Норматив на день',
                  ),
                ],
              ),
              if (!rowsFirst)
                PomodoroCapacityNotice(
                  summary: repo.pomodoroCapacityForDate(),
                  workMinutes: repo.settings['workMinutes'] as int,
                ),
              if (!compact)
                TextButton(
                  onPressed: () => editPomodoroCapacity(context, repo),
                  child: const Text('Изменить дневной лимит'),
                ),
              if (norms.isEmpty) const Text('Нормативы на сегодня не заданы.'),
              if (rowsFirst || !scrollChecks)
                checks
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: compact ? 180 : 280),
                  child: SingleChildScrollView(primary: false, child: checks),
                ),
              if (rowsFirst)
                PomodoroCapacityNotice(
                  summary: repo.pomodoroCapacityForDate(),
                  workMinutes: repo.settings['workMinutes'] as int,
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final day in days)
                  (() {
                    final cap = repo.pomodoroCapacityForDate(day);
                    return Chip(
                      backgroundColor: cap['over'] == true
                          ? const Color(0xffffeded)
                          : null,
                      label: Text(
                        '${day.substring(8)}.${day.substring(5, 7)} · ${cap['planned']} / ${cap['limit'] ?? '—'}',
                        style: TextStyle(
                          color: cap['over'] == true
                              ? const Color(0xffb3261e)
                              : null,
                        ),
                      ),
                    );
                  })(),
              ],
            ),
            const Text(
              'Суммарный план / дневной лимит · «—» — лимит не задан',
              style: TextStyle(fontSize: 12),
            ),
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
