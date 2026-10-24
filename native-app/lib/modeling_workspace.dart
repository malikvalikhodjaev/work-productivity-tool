import 'package:flutter/material.dart';

import 'domain.dart';
import 'modeler.dart';
import 'project_review.dart';
import 'repository.dart';
import 'portfolio_grid.dart';
import 'model_hierarchy.dart';
import 'section_analytics.dart';

class ModelingWorkspace extends StatefulWidget {
  final DashboardRepository repo;
  final Future<void> Function() createProject;
  final Future<void> Function(Json) editProject;
  final Future<void> Function(Json, Json?) editAlpha;
  final Future<void> Function(Json, Json) createInZone;
  final Future<void> Function(Json, Json) createChild;
  final Future<void> Function(Json) focusAlpha;
  final Future<void> Function(Json) linkSystem;
  final Widget Function(Json) characteristics;
  final Widget? systemsPanel;
  const ModelingWorkspace({
    super.key,
    required this.repo,
    required this.createProject,
    required this.editProject,
    required this.editAlpha,
    required this.createInZone,
    required this.createChild,
    required this.focusAlpha,
    required this.linkSystem,
    required this.characteristics,
    this.systemsPanel,
  });

  @override
  State<ModelingWorkspace> createState() => _ModelingWorkspaceState();
}

class _ModelingWorkspaceState extends State<ModelingWorkspace> {
  String query = '';
  String? selected;
  String? inspected;
  bool board = false;
  @override
  void initState() {
    super.initState();
    selected = widget.repo.local.get('modelerProjectId') as String?;
    board = widget.repo.local.get('projectView') == 'board';
  }

  void open(Json project) {
    widget.repo.local.set('modelerProjectId', project['id']);
    setState(() {
      selected = project['id'].toString();
      inspected = null;
    });
  }

  Future<void> copyProject([Json? source]) async {
    if (source?['pendingCopy'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Сначала синхронизируй исходную копию, затем её можно копировать дальше.',
          ),
        ),
      );
      return;
    }
    if (source != null) {
      final ids = widget.repo
          .entities('alphas', 'alpha')
          .where((a) => a['projectId'] == source['id'])
          .map((a) => a['id'])
          .toSet();
      final unsent = widget.repo.pending.any((q) {
        final body = object(q['body']), input = object(body['input']);
        return body['module'] == 'portfolio' &&
            (input['id'] == source['id'] ||
                input['projectId'] == source['id'] ||
                ids.contains(input['id']));
      });
      if (unsent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Сначала синхронизируй изменения исходного проекта. Набор из руководств доступен для новой копии без сети.',
            ),
          ),
        );
        return;
      }
    }
    final repo = widget.repo,
        catalog = rows(widget.repo.cache('portfolio')['projectTemplates']);
    if (source == null && catalog.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            repo.cache('portfolio')['templateError']?.toString() ??
                'No Data · пакет шаблонов пока не загружен.',
          ),
        ),
      );
      return;
    }
    Json definition = source == null
        ? catalog.first
        : sourceProjectDefinition(
            source,
            repo
                .entities('alphas', 'alpha')
                .where((a) => a['projectId'] == source['id'])
                .toList(),
          );
    var areas = rows(definition['areas'])
        .map((a) => a['id'].toString())
        .toSet();
    final draftKey = 'projectCopyForm:${source?['id'] ?? 'template'}',
        draft = object(
          repo.local.get('projectCopyForm:${source?['id'] ?? 'template'}'),
        );
    final name = TextEditingController(
      text:
          (draft['name'] ?? (source == null ? '' : '${source['name']} · копия'))
              .toString(),
    );
    String? message;
    bool saving = false;
    void keep() {
      repo.local.set(draftKey, {'name': name.text});
    }

    name.addListener(keep);
    final projectId = uuid.v4(), ids = <String, String>{};
    for (final item in source == null ? catalog : [definition]) {
      for (final alpha in rows(item['alphas'])) {
        ids.putIfAbsent(alpha['sourceId'].toString(), () => uuid.v4());
      }
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(
            source == null
                ? 'Новый проект из шаблона'
                : 'Копировать структуру проекта',
          ),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Название проекта',
                    ),
                  ),
                  if (source == null)
                    DropdownButtonFormField<String>(
                      initialValue: definition['id'].toString(),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Набор'),
                      items: [
                        for (final t in catalog)
                          DropdownMenuItem(
                            value: t['id'].toString(),
                            child: Text(t['title'].toString()),
                          ),
                      ],
                      onChanged: (id) => setDialog(() {
                        definition = catalog.firstWhere((t) => t['id'] == id);
                        areas = rows(definition['areas'])
                            .map((a) => a['id'].toString())
                            .toSet();
                      }),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    source == null
                        ? 'Сохранённый пакет · ${definition['capturedAt'] ?? 'No Data'}'
                        : 'Источник: ${source['name']}',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Копируется структура и подсказки. Факты, время, проектные имена и подтверждённые состояния не переносятся.',
                  ),
                  for (final area in rows(definition['areas']))
                    CheckboxListTile(
                      value: areas.contains(area['id']),
                      title: Text(area['title'].toString()),
                      onChanged: (checked) => setDialog(() {
                        checked == true
                            ? areas.add(area['id'].toString())
                            : areas.remove(area['id']);
                      }),
                    ),
                  Text(
                    'Будет создано альф и подальф: ${rows(definition['alphas']).where((a) => areas.contains(a['areaId'])).length}. Заполнено: 0.',
                  ),
                  if (message != null) Text(message!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Закрыть'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () {
                      try {
                        if (name.text.trim().isEmpty || areas.isEmpty) {
                          throw StateError(
                            'Назови проект и выбери хотя бы одну область.',
                          );
                        }
                        setDialog(() => saving = true);
                        final nodes = rows(definition['alphas'])
                            .where((a) => areas.contains(a['areaId']));
                        repo.gridCommand('copyProject', {
                          'clientId': projectId,
                          'name': name.text,
                          'expectedVersion': definition['version'],
                          'areaIds': areas.toList(),
                          'alphaIds': {
                            for (final a in nodes)
                              a['sourceId']: ids[a['sourceId']],
                          },
                          'localDefinition': definition,
                          if (source == null)
                            'templateId': definition['id']
                          else
                            'sourceProjectId': source['id'],
                        });
                        repo.local.remove(draftKey);
                        repo.local.set('modelerProjectId', projectId);
                        setState(() {
                          selected = projectId;
                          inspected = null;
                        });
                        Navigator.pop(dialogContext);
                      } catch (e) {
                        setDialog(() {
                          message = e.toString();
                          saving = false;
                        });
                      }
                    },
              child: const Text('Создать проект'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
  }

  Widget projectBoard(List<Json> projects) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final status in projectStatusNames.entries)
          SizedBox(
            width: 280,
            child: Card(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${status.value} · ${projects.where((p) => p['status'] == status.key).length}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final p in projects.where(
                      (p) => p['status'] == status.key,
                    ))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextButton(
                                onPressed: () => open(p),
                                child: Text(
                                  p['name'].toString(),
                                  textAlign: TextAlign.left,
                                ),
                              ),
                              Text(
                                '${projectPhaseNames[p['phase']]} · альф: ${object(p['summary'])['filled']} / ${object(p['summary'])['slots']}',
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                key: ValueKey('${p['id']}:${p['status']}'),
                                initialValue: p['status'].toString(),
                                isExpanded: true,
                                items: [
                                  for (final item in projectStatusNames.entries)
                                    DropdownMenuItem(
                                      value: item.key,
                                      child: Text(item.value),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value == null || value == p['status']) {
                                    return;
                                  }
                                  try {
                                    widget.repo.gridCommand('editCells', {
                                      'table': 'projects',
                                      'id': p['id'],
                                      'changes': [
                                        {
                                          'columnId': 'status',
                                          'before': p['status'],
                                          'value': value,
                                        },
                                      ],
                                    });
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                },
                              ),
                              TextButton(
                                onPressed: () => copyProject(p),
                                child: const Text('Копировать структуру'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!projects.any((p) => p['status'] == status.key))
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No Data'),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget cell(String text, {double width = 220}) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
    ),
  );

  Widget table(DataTable child) => Card(
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.repo,
    builder: (context, _) {
      final repo = widget.repo;
      final allAlphas = repo.entities('alphas', 'alpha');
      final projects = repo
          .entities('projects', 'project')
          .map((p) => modelProject(p, allAlphas))
          .toList();
      final shown = projects
          .where(
            (p) => p['name'].toString().toLowerCase().contains(
              query.toLowerCase(),
            ),
          )
          .toList();
      final project = projects.where((p) => p['id'] == selected).firstOrNull;
      final alphas = allAlphas
          .where((a) => a['projectId'] == selected)
          .toList();
      final alpha = alphas.where((a) => a['id'] == inspected).firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Мои проекты',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              TextButton.icon(
                onPressed: widget.createProject,
                icon: const Icon(Icons.add),
                label: const Text('Проект'),
              ),
            ],
          ),
          TextField(
            key: const ValueKey('project-search'),
            decoration: const InputDecoration(
              labelText: 'Найти проект',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Список'),
                    icon: Icon(Icons.table_rows_outlined),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Доска'),
                    icon: Icon(Icons.view_kanban_outlined),
                  ),
                ],
                selected: {board},
                onSelectionChanged: (value) {
                  widget.repo.local.set(
                    'projectView',
                    value.single ? 'board' : 'list',
                  );
                  setState(() => board = value.single);
                },
              ),
              TextButton.icon(
                onPressed: copyProject,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Из шаблона'),
              ),
            ],
          ),
          if (projects.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No Data · создай первый проект.'),
            ),
          if (board)
            projectBoard(shown)
          else
            PortfolioGrid(
              key: ValueKey('projects:${repo.serverId}'),
              repo: repo,
              table: 'projects',
              items: shown,
              addRow: widget.createProject,
              openRow: open,
            ),
          if (projects.isNotEmpty && shown.isEmpty)
            const Text('По этому запросу проектов нет.'),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(),
          ),
          Text(
            'Моделирование',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          if (project == null && projects.isNotEmpty)
            const Text('Выбери проект в таблице, чтобы открыть его альфы.'),
          if (project != null) ...[
            Text(
              'Альфы проекта',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  project['name'].toString(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton(
                  onPressed: () => widget.editProject(project),
                  child: const Text('Настроить проект'),
                ),
                TextButton.icon(
                  onPressed: () => widget.editAlpha(project, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Альфа'),
                ),
                TextButton(
                  onPressed: () => copyProject(project),
                  child: const Text('Копировать структуру'),
                ),
              ],
            ),
            const Text(
              'Опиши объект, его состояние и то, чем оно подтверждается. Можно начать с заметки; остальные поля заполнить позже.',
            ),
            const SizedBox(height: 12),
            if (alphas.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No Data · здесь пока нет альф. Нажми ＋ у нужной зоны.',
                ),
              ),
            PortfolioGrid(
              key: ValueKey('alphas:${repo.serverId}$selected'),
              repo: repo,
              table: 'alphas',
              items: alphas,
              addRow: () => widget.editAlpha(project, null),
              openRow: (row) {
                setState(() => inspected = row['id'].toString());
              },
              addChild: (row) => widget.createChild(project, row),
            ),
            if (alpha != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        alphaName(alpha),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      for (final item in {
                        'Описание и заметки': 'description',
                        'Критерий состояния': 'criteria',
                        'Подтверждение': 'evidence',
                        'Следующий шаг': 'nextStep',
                      }.entries) ...[
                        const SizedBox(height: 12),
                        Text(
                          item.key,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        SelectableText(
                          (alpha[item.value] ?? '').toString().isEmpty
                              ? 'No Data'
                              : alpha[item.value].toString(),
                        ),
                      ],
                      TextButton(
                        onPressed: () => widget.editAlpha(project, alpha),
                        child: const Text('Записать'),
                      ),
                      TemplateHints(alpha: alpha),
                      AlphaHistoryPanel(
                        key: ValueKey('history:${repo.base}:${alpha['id']}'),
                        repo: repo,
                        alpha: alpha,
                      ),
                    ],
                  ),
                ),
              ),
            ExpansionTile(
              title: const Text('Зоны и пробелы'),
              children: [
                for (final zone in rows(project['zones']))
                  Card(
                    child: ListTile(
                      leading: Icon(
                        zone['covered'] == true
                            ? Icons.check_circle_outline
                            : Icons.circle_outlined,
                      ),
                      title: Text(zone['title'].toString()),
                      subtitle: Text(
                        zone['covered'] == true
                            ? 'Состояние подтверждено'
                            : (zone['issues'] as List).join(' · '),
                      ),
                      trailing: IconButton(
                        tooltip: 'Добавить альфу в зону',
                        onPressed: () => widget.createInZone(project, zone),
                        icon: const Icon(Icons.add),
                      ),
                    ),
                  ),
              ],
            ),
            ExpansionTile(
              title: const Text('Характеристики системы'),
              children: [
                TextButton(
                  onPressed: () => widget.linkSystem(project),
                  child: const Text('Связать с системой'),
                ),
                widget.characteristics(project),
              ],
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Счётчик слотов относится к созданным карточкам. Полнота по обязательному шаблону: No Data · шаблон пока не выбран.',
              ),
            ),
          ],
          ?widget.systemsPanel,
          const SizedBox(height: 20),
          ExpansionTile(
            title: const Text('Регулярный обзор проектов'),
            children: [
              ProjectReview(
                repo: repo,
                openAlpha: (p, a) => widget.editAlpha(p, a),
              ),
            ],
          ),
          ModelAnalytics(repo: repo, projectId: selected),
        ],
      );
    },
  );
}

class AlphaHistoryPanel extends StatefulWidget {
  final DashboardRepository repo;
  final Json alpha;
  const AlphaHistoryPanel({super.key, required this.repo, required this.alpha});
  @override
  State<AlphaHistoryPanel> createState() => _AlphaHistoryPanelState();
}

class _AlphaHistoryPanelState extends State<AlphaHistoryPanel> {
  bool loading = false;
  String? note;
  String get cacheKey =>
      'alphaHistory:${widget.repo.base}:${widget.alpha['id']}';
  Future<void> load() async {
    if (loading) return;
    setState(() => loading = true);
    final base = widget.repo.base;
    final key = cacheKey;
    try {
      final result = await widget.repo.request(
        '/api/alphas/history?id=${Uri.encodeQueryComponent(widget.alpha['id'].toString())}',
      );
      if (widget.repo.base != base) return;
      widget.repo.local.capture(key, result);
      note = null;
    } catch (_) {
      note = 'Нет связи · показана история, ранее сохранённая на устройстве.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = rows(widget.repo.cache(cacheKey)['entries']).reversed
        .toList();
    final local = widget.repo.local.draft('alpha:${widget.alpha['id']}');
    return ExpansionTile(
      title: const Text('История альфы'),
      onExpansionChanged: (open) {
        if (open) load();
      },
      children: [
        if (loading) const LinearProgressIndicator(),
        if (local != null)
          const ListTile(
            title: Text('Есть изменения на устройстве'),
            subtitle: Text(
              'После синхронизации сервер сохранит подтверждённую версию в истории.',
            ),
          ),
        if (note != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(note!)),
        if (entries.isEmpty && !loading)
          const ListTile(title: Text('No Data · сохранённых версий пока нет')),
        for (final entry in entries)
          ExpansionTile(
            title: Text(entry['at'].toString()),
            subtitle: Text(
              alphaStateNames[object(entry['snapshot'])['state']] ?? 'No Data',
            ),
            children: [
              for (final item in {
                'Проектное имя': 'uniqueName',
                'Описание и заметки': 'description',
                'Критерий состояния': 'criteria',
                'Подтверждение': 'evidence',
                'Следующий шаг': 'nextStep',
                'Дата возврата': 'reviewDate',
              }.entries)
                ListTile(
                  title: Text(item.key),
                  subtitle: SelectableText(
                    (object(entry['snapshot'])[item.value] ?? '')
                            .toString()
                            .isEmpty
                        ? 'No Data'
                        : object(entry['snapshot'])[item.value].toString(),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
