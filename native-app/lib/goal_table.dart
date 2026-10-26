import 'dart:math';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'goal_progress.dart';
import 'goal_status.dart';
import 'goal_workspace.dart';
import 'goal_columns.dart';
import 'model_hierarchy.dart';
import 'repository.dart';
import 'workspace_table.dart';
import 'inline_cell.dart';
import 'activity_status.dart';

class GoalsTable extends StatefulWidget {
  final DashboardRepository repo;
  final List<Json> goals;
  final void Function(Json) edit, measure, child, history;
  final String? rootId;
  final String initialMode;
  final Widget Function(BuildContext)? timer;
  const GoalsTable({
    super.key,
    required this.repo,
    required this.goals,
    required this.edit,
    required this.measure,
    required this.child,
    required this.history,
    this.rootId,
    this.initialMode = 'current',
    this.timer,
  });
  @override
  State<GoalsTable> createState() => _GoalsTableState();
}

class _GoalsTableState extends State<GoalsTable> {
  String get preferenceKey =>
      'goalFilter:${widget.repo.serverId}:${widget.rootId ?? 'all'}';
  Json get filter => object(widget.repo.local.get(preferenceKey));
  String get mode => (filter['mode'] ?? widget.initialMode).toString();
  void setFilter(Json patch) {
    widget.repo.setUiPreference(preferenceKey, {...filter, ...patch});
    setState(() {});
  }

  void open(Json goal) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GoalFocusPage(
        repo: widget.repo,
        goalId: goal['id'].toString(),
        initialMode: mode,
        edit: widget.edit,
        measure: widget.measure,
        child: widget.child,
        history: widget.history,
        timer: widget.timer,
      ),
    ),
  );

  Future<void> rowAction(Json goal, String action) async {
    try {
      switch (action) {
        case 'open':
          open(goal);
          return;
        case 'edit':
          widget.edit(goal);
          return;
        case 'history':
          widget.history(goal);
          return;
        case 'child':
          widget.child(goal);
          return;
        case 'archive':
          widget.repo.editGoalField(
            goal['id'].toString(),
            'status',
            'archived',
            expectedGoal: goal,
          );
          break;
        case 'unarchive':
          final owner = widget.goals.firstWhere(
            (g) => g['id'] == (goal['_archiveOwner'] ?? goal['id']),
          );
          widget.repo.editGoalField(
            owner['id'].toString(),
            'status',
            'active',
            expectedGoal: owner,
          );
          break;
        case 'restore':
          final owner = widget.goals.firstWhere(
            (g) => g['id'] == (goal['_trashOwner'] ?? goal['id']),
          );
          widget.repo.editGoalField(
            owner['id'].toString(),
            'trashedAt',
            null,
            expectedGoal: owner,
          );
          break;
        case 'delete':
          final branch = filterGoalRows(
            widget.goals,
            mode: 'all',
            branchId: goal['id'].toString(),
          );
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Удалить цель?'),
              content: Text(
                '«${goal['title']}» будет перемещена в корзину${branch.length > 1 ? ' вместе с ветвью из ${branch.length - 1} подцелей' : ''}. Замеры и история сохранятся. Восстановить можно через фильтр «Корзина».',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Удалить'),
                ),
              ],
            ),
          );
          if (confirmed != true || !mounted) return;
          widget.repo.editGoalField(
            goal['id'].toString(),
            'trashedAt',
            DateTime.fromMillisecondsSinceEpoch(
              widget.repo.now,
              isUtc: true,
            ).toIso8601String(),
            expectedGoal: goal,
          );
          break;
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) error(e);
    }
  }

  Set<String> get collapsed =>
      (widget.repo.local.get('goalTableCollapsed') as List? ?? [])
          .whereType<String>()
          .toSet();
  void collapse(Set<String> ids) {
    widget.repo.setUiPreference('goalTableCollapsed', ids.toList());
    setState(() {});
  }

  void error(Object e) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
  Widget editable(String text, VoidCallback action) => TextButton(
    onPressed: action,
    style: TextButton.styleFrom(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
    ),
    child: Text(text, softWrap: true),
  );
  Widget field(Json goal, String id) {
    final text = id == 'title'
        ? goal['title'].toString()
        : id == 'unit' || id == 'dueDate' || id == 'physicalSystem'
        ? (goal[id] ?? '').toString()
        : goalNumber(goal[id]);
    if (goal['characteristicId'] != null) {
      return editable(
        text.isEmpty ? 'Заполнить' : text,
        () => widget.edit(goal),
      );
    }
    final draftKey = 'goalInline:${widget.repo.serverId}:${goal['id']}:$id';
    return InlineCell(
      key: ValueKey('goal-cell:$id:${goal['id']}'),
      text: goal[id]?.toString() ?? '',
      label: const {
        'title': 'Индикатор',
        'physicalSystem': 'Физическая система',
        'unit': 'Единица / период',
        'target': 'Предпочтительная мною шкала',
        'dueDate': 'Дедлайн цели · ГГГГ-ММ-ДД',
      }[id]!,
      maxLines: id == 'physicalSystem' ? 3 : 1,
      displayText: id == 'title' ? '${goal['_wbs']} · ${goal['title']}' : null,
      draft: object(widget.repo.local.get(draftKey))['text'] as String?,
      begin: () {
        if (widget.repo.local.get(draftKey) == null) {
          widget.repo.local.set(draftKey, {
            'text': goal[id]?.toString() ?? '',
            'base':
                widget.repo
                    .entities('goals', 'goal')
                    .where((g) => g['id'] == goal['id'])
                    .firstOrNull ??
                goal,
          });
        }
      },
      retain: (text) => widget.repo.local.set(draftKey, {
        ...object(widget.repo.local.get(draftKey)),
        'text': text,
      }),
      cancel: () => widget.repo.local.remove(draftKey),
      commit: (text) async {
        dynamic value = text;
        if (id == 'baseline' || id == 'target') {
          value = text.isEmpty ? null : num.tryParse(text.replaceAll(',', '.'));
          if (text.isNotEmpty && (value is! num || !value.isFinite)) {
            throw const FormatException('Укажи число.');
          }
        }
        if (id == 'title' && (text.trim().isEmpty || text.length > 200)) {
          throw const FormatException('Название: 1–200 символов.');
        }
        if (id == 'physicalSystem' && text.length > 2000) {
          throw const FormatException('Текст до 2000 символов.');
        }
        if (id == 'dueDate') {
          value = text.isEmpty ? null : text;
          if (text.isNotEmpty &&
              DateTime.tryParse(text)?.toIso8601String().substring(0, 10) !=
                  text) {
            throw const FormatException('Дата в формате ГГГГ-ММ-ДД.');
          }
        }
        final base = object(object(widget.repo.local.get(draftKey))['base']);
        widget.repo.editGoalField(
          goal['id'].toString(),
          id,
          value,
          expectedGoal: base.isEmpty ? null : base,
        );
        widget.repo.local.remove(draftKey);
      },
    );
  }

  Widget rowMenu(Json g) => PopupMenuButton<String>(
    key: ValueKey('goal-menu:${g['id']}'),
    tooltip: 'Меню цели',
    icon: const Icon(Icons.more_horiz),
    onSelected: (action) => rowAction(g, action),
    itemBuilder: (_) => [
      PopupMenuItem(
        key: ValueKey('goal-open:${g['id']}'),
        value: 'open',
        child: const Text('Открыть отдельно'),
      ),
      const PopupMenuItem(value: 'edit', child: Text('Изменить цель')),
      const PopupMenuItem(value: 'history', child: Text('История замеров')),
      if (g['_inTrash'] != true) ...[
        const PopupMenuItem(value: 'child', child: Text('Добавить подцель')),
        PopupMenuItem(
          value: g['_inArchive'] == true ? 'unarchive' : 'archive',
          child: Text(
            g['_inArchive'] == true ? 'Вернуть из архива' : 'В архив',
          ),
        ),
        const PopupMenuItem(value: 'delete', child: Text('Удалить строку')),
      ] else
        const PopupMenuItem(
          value: 'restore',
          child: Text('Восстановить из корзины'),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final controlScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final branchId = widget.rootId ?? filter['branch']?.toString();
    final items = filterGoalRows(
      widget.goals,
      mode: mode,
      status: (filter['status'] ?? '').toString(),
      branchId: branchId?.isEmpty == true ? null : branchId,
    );
    final parents = items
        .where((g) => items.any((c) => parentOf(c) == g['id']))
        .map((g) => g['id'].toString())
        .toSet();
    final tools = <Widget>[
      Text('Индикаторов: ${items.length}'),
      PopupMenuButton<String>(
        tooltip: 'Иерархия целей',
        onSelected: (action) => collapse(action == 'expand' ? {} : parents),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'expand', child: Text('Раскрыть все')),
          PopupMenuItem(value: 'collapse', child: Text('Свернуть все')),
        ],
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text('Иерархия'), Icon(Icons.arrow_drop_down, size: 18)],
          ),
        ),
      ),
      SizedBox(
        width: 155 * controlScale,
        child: DropdownButtonFormField<String>(
          key: ValueKey('goal-filter-mode:$mode'),
          initialValue: mode,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Показывать',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'current', child: Text('Текущие цели')),
            DropdownMenuItem(value: 'archived', child: Text('В архиве')),
            DropdownMenuItem(value: 'all', child: Text('Все')),
            DropdownMenuItem(value: 'trash', child: Text('Корзина')),
          ],
          onChanged: (v) {
            if (v != null) {
              setFilter({'mode': v, 'status': '', 'branch': ''});
            }
          },
        ),
      ),
      SizedBox(
        width: 175 * controlScale,
        child: DropdownButtonFormField<String>(
          key: ValueKey('goal-filter-status:${filter['status']}'),
          initialValue: (filter['status'] ?? '').toString(),
          isExpanded: true,
          itemHeight: null,
          decoration: const InputDecoration(
            labelText: 'Статус цели',
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Любой статус')),
            for (final s in goalStatusOptions.entries.where(
              (s) => s.key != 'archived',
            ))
              DropdownMenuItem(value: s.key, child: Text(s.value)),
          ],
          onChanged: (v) {
            if (v != null) setFilter({'status': v});
          },
        ),
      ),
      if (widget.rootId == null)
        SizedBox(
          width: 210 * controlScale,
          child: DropdownButtonFormField<String>(
            key: ValueKey('goal-filter-branch:${filter['branch']}'),
            initialValue:
                filterGoalRows(
                  widget.goals,
                  mode: mode,
                ).any((g) => g['id'] == filter['branch'])
                ? filter['branch'].toString()
                : '',
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(
              labelText: 'Цель и её подцели',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Все ветви')),
              for (final g in filterGoalRows(widget.goals, mode: mode))
                DropdownMenuItem(
                  value: g['id'].toString(),
                  child: Text('${g['_sourceWbs']} · ${g['title']}'),
                ),
            ],
            onChanged: (v) {
              if (v != null) setFilter({'branch': v});
            },
          ),
        ),
      TextButton.icon(
        onPressed: widget.repo.canUndoGoal
            ? () {
                try {
                  widget.repo.undoGoalField();
                } catch (e) {
                  error(e);
                }
              }
            : null,
        icon: const Icon(Icons.undo),
        label: const Text('Отменить правку'),
      ),
    ];
    return Column(
      key: const ValueKey('goals-table-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty)
          Text(
            widget.goals.isEmpty
                ? 'Добавь первую цель кнопкой «＋ Цель».'
                : 'По этим фильтрам целей нет. Измени или сбрось фильтры.',
          ),
        WorkspaceTable(
          key: const ValueKey('goals-hierarchy-table'),
          repo: widget.repo,
          viewKey:
              'goalWorkbench:${widget.repo.serverId}:${widget.rootId ?? 'all'}',
          grouping: false,
          tools: tools,
          compactToolbar: true,
          reset: () =>
              setFilter({'mode': 'current', 'status': '', 'branch': ''}),
          items: items,
          collapsed: (filter['status'] ?? '').toString().isNotEmpty
              ? const {}
              : collapsed,
          rowKey: (r) => 'goal-row:${r['id']}',
          rename: (column) => editGoalColumn(
            context,
            widget.repo,
            column: widget.repo.goalColumns().firstWhere(
              (c) => c['id'] == column.id,
            ),
          ),
          addColumn: () => editGoalColumn(context, widget.repo),
          columns: [
            for (final c in widget.repo.goalColumns())
              WorkColumn(
                c['id'].toString(),
                c['title'].toString(),
                width: (c['width'] as num? ?? 200).toDouble(),
                hint: c['id'] == 'dueDate' ? goalDeadlineHint : null,
              ),
          ],
          value: (g, id) => id == '*'
              ? '${g['title']} ${g['physicalSystem'] ?? ''} ${g['unit'] ?? ''} ${object(g['customValues']).values.join(' ')} ${goalStatusLabel(g['status'])}'
              : id == 'measurement'
              ? object(g['measurement'])['date']
              : id == 'status'
              ? goalStatusLabel(g[id])
              : object(g['customValues']).containsKey(id)
              ? object(g['customValues'])[id]
              : g[id],
          cell: (context, g, col) {
            switch (col.id) {
              case 'title':
                return Padding(
                  padding: EdgeInsets.only(
                    left: min((g['_depth'] as int) * 14.0, 56),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (g['_hasChildren'] == true)
                        IconButton(
                          key: ValueKey('goal-toggle:${g['id']}'),
                          tooltip: collapsed.contains(g['id'])
                              ? 'Раскрыть подцели'
                              : 'Свернуть подцели',
                          onPressed: () {
                            final next = {...collapsed};
                            if (!next.remove(g['id'])) {
                              next.add(g['id'].toString());
                            }
                            collapse(next);
                          },
                          icon: Icon(
                            collapsed.contains(g['id'])
                                ? Icons.chevron_right
                                : Icons.expand_more,
                          ),
                        ),
                      Expanded(child: field(g, 'title')),
                      rowMenu(g),
                    ],
                  ),
                );
              case 'physicalSystem':
              case 'target':
              case 'unit':
              case 'dueDate':
                return field(g, col.id);
              case 'current':
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeyedSubtree(
                      key: ValueKey('goal-cell:current:${g['id']}'),
                      child: editable(
                        goalNumber(g['current']),
                        () => widget.measure(g),
                      ),
                    ),
                    if (object(g['measurement'])['pending'] == true)
                      const Text('На устройстве'),
                  ],
                );
              case 'delta':
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (g['delta'] is num)
                      Text(
                        'С начала: ${g['delta'] > 0 ? '+' : ''}${goalDifferenceNumber(g['delta'])} ${g['unit'] ?? ''}'
                        '${g['changePercent'] is num ? ' (${g['changePercent'] > 0 ? '+' : ''}${goalNumber((g['changePercent'] as num).round())}%)' : ''}',
                      )
                    else
                      editable('Заполнить', () => widget.measure(g)),
                    if (g['lastChange'] is num)
                      Text(
                        'К прошлому: ${g['lastChange'] > 0 ? '+' : ''}${goalDifferenceNumber(g['lastChange'])}',
                      ),
                    if (g['percent'] is num) ...[
                      const SizedBox(height: 6),
                      Text(
                        'К предпочтительной: ${g['percent']}%${g['reached'] == true ? ' · достигнуто' : ''}',
                      ),
                      LinearProgressIndicator(
                        value: ((g['percent'] as num) / 100)
                            .clamp(0, 1)
                            .toDouble(),
                      ),
                    ],
                  ],
                );
              case 'status':
                return DropdownButtonFormField<String>(
                  itemHeight: null,
                  key: ValueKey('goal-status:${g['id']}:${g['status']}'),
                  initialValue: goalStatusOptions.containsKey(g['status'])
                      ? g['status'].toString()
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                  ),
                  items: [
                    for (final status in goalStatusOptions.entries)
                      DropdownMenuItem(
                        value: status.key,
                        child: Text(status.value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null || value == g['status']) return;
                    try {
                      widget.repo.editGoalField(
                        g['id'].toString(),
                        'status',
                        value,
                        expectedGoal: g,
                      );
                    } catch (e) {
                      error(e);
                    }
                  },
                );
              default:
                return GoalCustomCell(
                  repo: widget.repo,
                  goal: g,
                  column: widget.repo.goalColumns().firstWhere(
                    (c) => c['id'] == col.id,
                  ),
                );
            }
          },
        ),
      ],
    );
  }
}

/// A route into any branch, never a copy or a reparenting of its goals.
class GoalFocusPage extends StatelessWidget {
  final DashboardRepository repo;
  final String goalId, initialMode;
  final void Function(Json) edit, measure, child, history;
  final Widget Function(BuildContext)? timer;
  const GoalFocusPage({
    super.key,
    required this.repo,
    required this.goalId,
    required this.edit,
    required this.measure,
    required this.child,
    required this.history,
    this.initialMode = 'current',
    this.timer,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final goals = projectedGoals(repo);
      final root = goals.where((g) => g['id'] == goalId).firstOrNull;
      final ancestors = <Json>[], seen = <String>{goalId};
      String? id = root == null ? null : parentOf(root);
      while (id != null && seen.add(id)) {
        final parent = goals.where((g) => g['id'] == id).firstOrNull;
        if (parent == null) break;
        ancestors.insert(0, parent);
        id = parentOf(parent);
      }
      return Scaffold(
        key: ValueKey('goal-focus:$goalId'),
        appBar: AppBar(
          title: const Text('Моделирование цели'),
          actions: [
            ActivityStatus(repo: repo, compact: true, showTimer: false),
          ],
        ),
        bottomNavigationBar: timer?.call(context),
        body: root == null
            ? const Center(
                child: Text(
                  'Цель пока недоступна. Вернись к списку и проверь синхронизацию.',
                ),
              )
            : SingleChildScrollView(
                key: PageStorageKey('goal-focus-scroll:$goalId'),
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 600 ? 12 : 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (ancestors.isNotEmpty)
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final parent in ancestors)
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute<void>(
                                      builder: (_) => GoalFocusPage(
                                        repo: repo,
                                        goalId: parent['id'].toString(),
                                        edit: edit,
                                        measure: measure,
                                        child: child,
                                        history: history,
                                        initialMode: initialMode,
                                        timer: timer,
                                      ),
                                    ),
                                  ),
                              child: Text('${parent['title']} /'),
                            ),
                        ],
                      ),
                    Text(
                      root['title'].toString(),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => edit(root),
                          child: const Text('Изменить цель'),
                        ),
                        TextButton(
                          onPressed: () => child(root),
                          child: const Text('＋ Подцель'),
                        ),
                        TextButton(
                          onPressed: () => history(root),
                          child: const Text('История замеров'),
                        ),
                      ],
                    ),
                    GoalsTable(
                      key: ValueKey('goal-focus-table:$goalId'),
                      repo: repo,
                      goals: goals,
                      rootId: goalId,
                      initialMode: initialMode,
                      edit: edit,
                      measure: measure,
                      child: child,
                      history: history,
                      timer: timer,
                    ),
                  ],
                ),
              ),
      );
    },
  );
}
