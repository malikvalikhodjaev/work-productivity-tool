import 'dart:math';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'goal_progress.dart';
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
        'baseline': 'Было',
        'target': 'Хочу',
        'dueDate': 'Срок · ГГГГ-ММ-ДД',
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
            'Ячейка — изменить. Для текущего значения открывается новый замер с датой. У каждой цели свой замер; прогресс подцелей не складывается.',
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
              WorkColumn('baseline', 'Было'),
              WorkColumn('current', 'Сейчас'),
              WorkColumn('target', 'Хочу'),
              WorkColumn('delta', 'Изменение', width: 190),
              WorkColumn('percent', 'Прогресс', width: 190),
              WorkColumn('measurement', 'Дата замера'),
              WorkColumn('dueDate', 'Срок'),
              WorkColumn('status', 'Состояние'),
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
                case 'baseline':
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
                  return g['delta'] is num
                      ? Text(
                          '${g['delta'] > 0 ? '+' : ''}${goalNumber(g['delta'])}'
                          '${g['lastChange'] is num ? '\nК прошлому: ${goalNumber(g['lastChange'])}' : ''}',
                        )
                      : editable(
                          'Заполнить',
                          () => g['current'] == null
                              ? widget.measure(g)
                              : widget.edit(g),
                        );
                case 'percent':
                  return g['percent'] is num
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${g['percent']}%${g['reached'] == true ? ' · достигнуто' : ''}',
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: (g['percent'] as num) / 100,
                            ),
                          ],
                        )
                      : editable('Заполнить шкалу', () => widget.edit(g));
                case 'measurement':
                  return editable(
                    object(g['measurement'])['date']?.toString() ?? 'Заполнить',
                    () => object(g['measurement'])['date'] == null
                        ? widget.measure(g)
                        : widget.history(g),
                  );
                case 'status':
                  return editable(switch (g['status']) {
                    'active' => 'Активная',
                    'paused' => 'На паузе',
                    'archived' => 'В архиве',
                    _ => 'Заполнить',
                  }, () => widget.edit(g));
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
