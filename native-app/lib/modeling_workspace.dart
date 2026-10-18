import 'package:flutter/material.dart';

import 'domain.dart';
import 'modeler.dart';
import 'project_review.dart';
import 'repository.dart';

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
  });

  @override
  State<ModelingWorkspace> createState() => _ModelingWorkspaceState();
}

class _ModelingWorkspaceState extends State<ModelingWorkspace> {
  String query = '';
  String? selected;
  String? inspected;
  @override
  void initState() {
    super.initState();
    selected = widget.repo.local.get('modelerProjectId') as String?;
  }

  void open(Json project) {
    widget.repo.local.set('modelerProjectId', project['id']);
    setState(() {
      selected = project['id'].toString();
      inspected = null;
    });
  }

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
              Text('Проекты', style: Theme.of(context).textTheme.headlineSmall),
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
          if (projects.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No Data · создай первый проект.'),
            ),
          if (projects.isNotEmpty)
            table(
              DataTable(
                columnSpacing: 20,
                horizontalMargin: 16,
                dataRowMinHeight: 58,
                dataRowMaxHeight: 80,
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Проект')),
                  DataColumn(label: Text('Состояние')),
                  DataColumn(label: Text('Слоты\nзаполнено / создано')),
                  DataColumn(label: Text('Зоны с пробелами')),
                  DataColumn(label: Text('К возврату')),
                  DataColumn(label: Text('')),
                ],
                rows: [
                  for (final p in shown)
                    DataRow(
                      key: ValueKey('project:${p['id']}'),
                      selected: p['id'] == selected,
                      onSelectChanged: (_) => open(p),
                      cells: [
                        DataCell(
                          TextButton(
                            onPressed: () => open(p),
                            child: cell(p['name'].toString(), width: 200),
                          ),
                        ),
                        DataCell(
                          cell(
                            '${projectStatusNames[p['status']] ?? p['status']}\n${projectPhaseNames[p['phase']] ?? p['phase']}',
                            width: 150,
                          ),
                        ),
                        DataCell(
                          Text(
                            '${object(p['summary'])['filled']} / ${object(p['summary'])['slots']}',
                          ),
                        ),
                        DataCell(
                          Text(
                            rows(p['zones']).isEmpty
                                ? 'No Data'
                                : '${object(p['summary'])['gaps']} / ${object(p['summary'])['totalZones']}',
                          ),
                        ),
                        DataCell(
                          Text(
                            '${allAlphas.where((a) => a['projectId'] == p['id'] && (a['reviewDate'] ?? '').toString().isNotEmpty && a['reviewDate'].toString().compareTo(today()) <= 0).length}',
                          ),
                        ),
                        DataCell(
                          TextButton(
                            onPressed: () => open(p),
                            child: const Text('Открыть моделер'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          if (projects.isNotEmpty && shown.isEmpty)
            const Text('По этому запросу проектов нет.'),
          const SizedBox(height: 16),
          if (project == null && projects.isNotEmpty)
            const Text('Выбери проект в таблице, чтобы открыть его альфы.'),
          if (project != null) ...[
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
              ],
            ),
            const Text(
              'Опиши объект, его состояние и то, чем оно подтверждается. Можно начать с заметки; остальные поля заполнить позже.',
            ),
            const SizedBox(height: 12),
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
            if (alphas.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No Data · здесь пока нет альф. Нажми ＋ у нужной зоны.',
                ),
              ),
            if (alphas.isNotEmpty)
              table(
                DataTable(
                  columnSpacing: 20,
                  horizontalMargin: 16,
                  showCheckboxColumn: false,
                  dataRowMinHeight: 70,
                  dataRowMaxHeight: 100,
                  columns: const [
                    DataColumn(label: Text('Альфа')),
                    DataColumn(label: Text('Состояние')),
                    DataColumn(label: Text('Следующий шаг')),
                    DataColumn(label: Text('Вернуться')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final a in alphas)
                      DataRow(
                        key: ValueKey('alpha:${a['id']}'),
                        selected: inspected == a['id'],
                        onSelectChanged: (_) =>
                            setState(() => inspected = a['id'].toString()),
                        cells: [
                          DataCell(
                            cell(
                              '${(a['parentId'] ?? '').toString().isEmpty ? '' : '↳ '}${alphaName(a)}\n${a['typeName'] ?? ''}',
                              width: 240,
                            ),
                          ),
                          DataCell(
                            cell(
                              alphaStateNames[a['state']] ?? 'No Data',
                              width: 150,
                            ),
                          ),
                          DataCell(
                            cell(
                              (a['nextStep'] ?? '').toString().isEmpty
                                  ? 'No Data'
                                  : a['nextStep'].toString(),
                              width: 250,
                            ),
                          ),
                          DataCell(
                            Text(
                              (a['reviewDate'] ?? '').toString().isEmpty
                                  ? 'No Data'
                                  : a['reviewDate'].toString(),
                            ),
                          ),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Записать',
                                  onPressed: () => widget.editAlpha(project, a),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Фокус',
                                  onPressed: () => widget.focusAlpha(a),
                                  icon: const Icon(Icons.play_arrow),
                                ),
                                IconButton(
                                  tooltip: 'Подальфа',
                                  onPressed: () =>
                                      widget.createChild(project, a),
                                  icon: const Icon(Icons.account_tree_outlined),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
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
