import 'dart:math';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'goal_progress.dart';
import 'goal_status.dart';
import 'model_hierarchy.dart';
import 'repository.dart';
import 'workspace_table.dart';
import 'inline_cell.dart';

class GoalsTable extends StatefulWidget {
  final DashboardRepository repo;
  final List<Json> goals;
  final void Function(Json) edit, measure, child, history;
  const GoalsTable({
    super.key,
    required this.repo,
    required this.goals,
    required this.edit,
    required this.measure,
    required this.child,
    required this.history,
  });
  @override
  State<GoalsTable> createState() => _GoalsTableState();
}

class _GoalsTableState extends State<GoalsTable> {
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
        : id == 'unit' || id == 'dueDate'
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
        'title': 'Цель',
        'unit': 'Единица / период',
        'target': 'Предпочтительная мною шкала',
        'dueDate': 'Дедлайн цели · ГГГГ-ММ-ДД',
      }[id]!,
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

  @override
  Widget build(BuildContext context) {
    final archived = widget.repo.local.get('goalTableShowArchived') == true;
    final items = widget.goals
        .where((g) => archived || g['status'] != 'archived')
        .toList();
    final parents = items
        .where((g) => items.any((c) => parentOf(c) == g['id']))
        .map((g) => g['id'].toString())
        .toSet();
    return Column(
      key: const ValueKey('goals-table-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Целей: ${items.length}'),
            TextButton(
              onPressed: parents.isEmpty ? null : () => collapse({}),
              child: const Text('Раскрыть все'),
            ),
            TextButton(
              onPressed: parents.isEmpty ? null : () => collapse(parents),
              child: const Text('Свернуть все'),
            ),
            FilterChip(
              label: const Text('Показывать архив'),
              selected: archived,
              onSelected: (v) {
                widget.repo.setUiPreference('goalTableShowArchived', v);
                setState(() {});
              },
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
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'Текущее значение открывает новый замер. Дата сохраняется автоматически, предыдущие значения — в истории. У каждой цели своя шкала; изменения подцелей не складываются.',
          ),
        ),
        if (items.isEmpty)
          const Text('Заполнить · добавь первую цель кнопкой «＋ Цель».'),
        if (items.isNotEmpty)
          WorkspaceTable(
            key: const ValueKey('goals-hierarchy-table'),
            repo: widget.repo,
            viewKey: 'goalWorkbench:${widget.repo.serverId}',
            items: items,
            collapsed: collapsed,
            rowKey: (r) => 'goal-row:${r['id']}',
            columns: const [
              WorkColumn('title', 'Цель', width: 340),
              WorkColumn('unit', 'Единица / период'),
              WorkColumn('current', 'Шкала/характеристика сейчас', width: 240),
              WorkColumn('target', 'Предпочтительная мною шкала', width: 240),
              WorkColumn('delta', 'Изменение', width: 260),
              WorkColumn(
                'dueDate',
                'Дедлайн цели',
                hint: goalDeadlineHint,
                width: 200,
              ),
              WorkColumn('status', 'Статус цели'),
              WorkColumn('_actions', 'Действия', width: 280),
            ],
            value: (g, id) => id == '*'
                ? g.values.join(' ')
                : id == 'measurement'
                ? object(g['measurement'])['date']
                : g[id],
            cell: (context, g, col) {
              switch (col.id) {
                case 'title':
                  return Padding(
                    padding: EdgeInsets.only(
                      left: min((g['_depth'] as int) * 14.0, 56),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                      ],
                    ),
                  );
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
                          'С начала: ${g['delta'] > 0 ? '+' : ''}${goalNumber(g['delta'])} ${g['unit'] ?? ''}'
                          '${g['changePercent'] is num ? ' (${g['changePercent'] > 0 ? '+' : ''}${goalNumber((g['changePercent'] as num).round())}%)' : ''}',
                        )
                      else
                        editable('Заполнить', () => widget.measure(g)),
                      if (g['lastChange'] is num)
                        Text(
                          'К прошлому: ${g['lastChange'] > 0 ? '+' : ''}${goalNumber(g['lastChange'])}',
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
                    key: ValueKey('goal-status:${g['id']}:${g['status']}'),
                    initialValue: goalStatusOptions.containsKey(g['status'])
                        ? g['status'].toString()
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Статус цели'),
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
                  return Wrap(
                    children: [
                      TextButton(
                        onPressed: () => widget.edit(g),
                        child: const Text('Подробности'),
                      ),
                      TextButton(
                        onPressed: () => widget.measure(g),
                        child: const Text('Новый замер'),
                      ),
                      IconButton(
                        key: ValueKey('goal-history:${g['id']}'),
                        tooltip: 'История замеров',
                        onPressed: () => widget.history(g),
                        icon: const Icon(Icons.history),
                      ),
                      IconButton(
                        key: ValueKey('goal-child:${g['id']}'),
                        tooltip: 'Добавить подцель',
                        onPressed: () => widget.child(g),
                        icon: const Icon(Icons.account_tree_outlined),
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
