import 'dart:math';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'inline_cell.dart';
import 'model_link.dart';
import 'modeler.dart';
import 'repository.dart';
import 'workspace_table.dart';

List<Json> projectModelRows(List<Json> projects, List<Json> alphas) => [
  for (final p in projects)
    {
      ...p,
      '_source': p,
      '_kind': 'project',
      'id': 'project:${p['id']}',
      'parentId': p['parentId'] == null || p['parentId'] == ''
          ? null
          : 'project:${p['parentId']}',
      'title': p['name'],
    },
  for (final a in alphas)
    {
      ...a,
      '_source': a,
      '_kind': 'alpha',
      'id': 'alpha:${a['id']}',
      'parentId': a['parentId'] == null || a['parentId'] == ''
          ? 'project:${a['projectId']}'
          : 'alpha:${a['parentId']}',
      'title': (a['uniqueName'] ?? '').toString().isEmpty
          ? a['typeName']
          : a['uniqueName'],
    },
];

class ProjectModelsTable extends StatefulWidget {
  final DashboardRepository repo;
  final List<Json> projects, alphas;
  final ValueChanged<Json> openProject, openAlpha;
  final void Function(Json) addAlpha, addChild;
  const ProjectModelsTable({
    super.key,
    required this.repo,
    required this.projects,
    required this.alphas,
    required this.openProject,
    required this.openAlpha,
    required this.addAlpha,
    required this.addChild,
  });
  @override
  State<ProjectModelsTable> createState() => _ProjectModelsTableState();
}

class _ProjectModelsTableState extends State<ProjectModelsTable> {
  String get collapseKey => 'projectModelTree:${widget.repo.serverId}';
  Set<String> get collapsed =>
      (widget.repo.local.get(collapseKey) as List? ?? [])
          .cast<String>()
          .toSet();
  void collapse(Set<String> ids) {
    widget.repo.setUiPreference(collapseKey, ids.toList());
    setState(() {});
  }

  void open(Json row) => row['_kind'] == 'project'
      ? widget.openProject(object(row['_source']))
      : widget.openAlpha(object(row['_source']));
  Widget field(Json row, String column) {
    final source = object(row['_source']);
    final table = row['_kind'] == 'project' ? 'projects' : 'alphas';
    final draftKey =
        'modelTreeCell:${widget.repo.serverId}:$table:${source['id']}:$column';
    final draft = object(widget.repo.local.get(draftKey));
    return InlineCell(
      key: ValueKey('model-tree-cell:${row['id']}:$column'),
      text: (source[column] ?? '').toString(),
      label: column == 'modelUrl'
          ? 'Ссылка на модель · HTTP / HTTPS'
          : 'Описание и заметки',
      maxLines: column == 'description' ? 6 : 1,
      draft: draft['text'] as String?,
      begin: () {
        if (widget.repo.local.get(draftKey) == null) {
          widget.repo.local.set(draftKey, {
            'text': source[column] ?? '',
            'before': source[column],
          });
        }
      },
      retain: (text) => widget.repo.local.set(draftKey, {
        ...object(widget.repo.local.get(draftKey)),
        'text': text,
      }),
      cancel: () => widget.repo.local.remove(draftKey),
      commit: (text) async {
        if (column == 'modelUrl' &&
            text.isNotEmpty &&
            modelLinkUri(text) == null) {
          throw ArgumentError('Укажи HTTP / HTTPS URL без логина и пароля.');
        }
        final saved = object(widget.repo.local.get(draftKey));
        widget.repo.editGridCell(
          table,
          source['id'].toString(),
          column,
          saved.containsKey('before') ? saved['before'] : source[column],
          text,
        );
        widget.repo.local.remove(draftKey);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = projectModelRows(widget.projects, widget.alphas);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          children: [
            TextButton(
              onPressed: () => collapse({}),
              child: const Text('Раскрыть все уровни'),
            ),
            TextButton(
              onPressed: () =>
                  collapse(items.map((r) => r['id'].toString()).toSet()),
              child: const Text('Свернуть все уровни'),
            ),
          ],
        ),
        WorkspaceTable(
          key: const ValueKey('project-models-table'),
          repo: widget.repo,
          viewKey: 'projectModelsView:${widget.repo.serverId}',
          items: items,
          collapsed: collapsed,
          columns: const [
            WorkColumn('title', 'Проект / альфа', width: 340),
            WorkColumn('_kind', 'Тип строки'),
            WorkColumn('state', 'Статус / состояние', width: 200),
            WorkColumn('modelUrl', 'Ссылка на модель', width: 300),
            WorkColumn('description', 'Описание и заметки', width: 340),
            WorkColumn('_actions', 'Действия', width: 250),
          ],
          value: (r, id) =>
              id == '*' ? r.values.whereType<String>().join(' ') : r[id],
          cell: (context, row, column) {
            final source = object(row['_source']),
                project = row['_kind'] == 'project';
            switch (column.id) {
              case 'title':
                return Padding(
                  padding: EdgeInsets.only(
                    left: min((row['_depth'] as int) * 16.0, 80),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (row['_hasChildren'] == true)
                        IconButton(
                          key: ValueKey('model-tree-toggle:${row['id']}'),
                          tooltip: collapsed.contains(row['id'])
                              ? 'Раскрыть уровень'
                              : 'Свернуть уровень',
                          onPressed: () {
                            final next = collapsed;
                            if (!next.remove(row['id'])) {
                              next.add(row['id'].toString());
                            }
                            collapse(next);
                          },
                          icon: Icon(
                            collapsed.contains(row['id'])
                                ? Icons.chevron_right
                                : Icons.expand_more,
                          ),
                        ),
                      Expanded(
                        child: TextButton(
                          onPressed: () => open(row),
                          child: Text('${row['_wbs']} · ${row['title']}'),
                        ),
                      ),
                    ],
                  ),
                );
              case '_kind':
                return Text(project ? 'Проект' : 'Альфа');
              case 'state':
                return Text(
                  project
                      ? const {
                              'active': 'Активный',
                              'paused': 'На паузе',
                              'closed': 'Закрыт',
                            }[source['status']] ??
                            'Заполнить'
                      : alphaStateNames[source['state']] ?? 'Заполнить',
                );
              case 'modelUrl':
                return project
                    ? const Text('—')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          field(row, 'modelUrl'),
                          ModelLink(
                            value: (source['modelUrl'] ?? '').toString(),
                          ),
                        ],
                      );
              case 'description':
                return field(row, 'description');
              default:
                return Wrap(
                  children: [
                    TextButton(
                      onPressed: () => open(row),
                      child: const Text('Подробности'),
                    ),
                    TextButton(
                      onPressed: () => project
                          ? widget.addAlpha(source)
                          : widget.addChild(source),
                      child: Text(project ? '＋ Альфа' : '＋ Подальфа'),
                    ),
                  ],
                );
            }
          },
        ),
      ],
    );
  }
}
