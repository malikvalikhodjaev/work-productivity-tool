import 'dart:math';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'goal_progress.dart';
import 'model_hierarchy.dart';
import 'repository.dart';

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
  final horizontal = ScrollController();

  @override
  void dispose() {
    horizontal.dispose();
    super.dispose();
  }

  void collapse(Set<String> ids) {
    widget.repo.setUiPreference('goalTableCollapsed', ids.toList());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final archived = widget.repo.local.get('goalTableShowArchived') == true;
    final items = widget.goals
        .where((g) => archived || g['status'] != 'archived')
        .toList();
    final collapsed =
        (widget.repo.local.get('goalTableCollapsed') as List? ?? [])
            .whereType<String>()
            .toSet();
    final shown = hierarchyRows(items, collapsed: collapsed);
    final parents = items
        .where((g) => items.any((c) => parentOf(c) == g['id']))
        .map((g) => g['id'].toString())
        .toSet();

    void fillProgress(Json g) {
      if (g['current'] == null) {
        widget.measure(g);
      } else {
        widget.edit(g);
      }
    }

    Widget editable(
      String label,
      VoidCallback action, {
      bool missing = false,
    }) => TextButton(
      onPressed: action,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        textStyle: TextStyle(
          fontWeight: missing ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      child: Text(label, softWrap: true),
    );

    Widget number(Json g, String field, VoidCallback action) => KeyedSubtree(
      key: ValueKey('goal-cell:$field:${g['id']}'),
      child: editable(goalNumber(g[field]), action, missing: g[field] == null),
    );

    return Column(
      key: const ValueKey('goals-table-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
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
              onSelected: (value) {
                widget.repo.setUiPreference('goalTableShowArchived', value);
                setState(() {});
              },
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'Нажми ячейку, чтобы заполнить или изменить её. Стрелка рядом с целью раскрывает подцели. У каждой цели свой замер; прогресс подцелей не складывается.',
          ),
        ),
        if (items.isEmpty)
          const Text('Заполнить · добавь первую цель кнопкой «＋ Цель».'),
        if (items.isNotEmpty)
          Scrollbar(
            controller: horizontal,
            thumbVisibility: true,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            child: SingleChildScrollView(
              key: const ValueKey('goals-table-horizontal-scroll'),
              controller: horizontal,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 14),
              child: DataTable(
                key: const ValueKey('goals-hierarchy-table'),
                horizontalMargin: 12,
                columnSpacing: 20,
                headingRowColor: const WidgetStatePropertyAll(
                  Color(0xffe9eeeb),
                ),
                dataRowMinHeight: 64,
                dataRowMaxHeight: double.infinity,
                columns: const [
                  DataColumn(label: Text('Цель')),
                  DataColumn(label: Text('Единица / период')),
                  DataColumn(label: Text('Было')),
                  DataColumn(label: Text('Сейчас')),
                  DataColumn(label: Text('Хочу')),
                  DataColumn(label: Text('Изменение')),
                  DataColumn(label: Text('Прогресс')),
                  DataColumn(label: Text('Дата замера')),
                  DataColumn(label: Text('Срок')),
                  DataColumn(label: Text('Состояние')),
                  DataColumn(label: Text('Действия')),
                ],
                rows: [
                  for (final g in shown)
                    DataRow(
                      key: ValueKey('goal-row:${g['id']}'),
                      color: WidgetStatePropertyAll(
                        g['_depth'] == 0
                            ? const Color(0xfff1f4f2)
                            : Colors.white,
                      ),
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 320,
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: min((g['_depth'] as int) * 18.0, 90),
                              ),
                              child: Row(
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
                                    )
                                  else
                                    const SizedBox(width: 40),
                                  Expanded(
                                    child: editable(
                                      '${g['_wbs']} · ${g['title']}',
                                      () => widget.edit(g),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 140,
                            child: editable(
                              (g['unit'] ?? '').toString().isEmpty
                                  ? 'Заполнить'
                                  : g['unit'].toString(),
                              () => widget.edit(g),
                              missing: (g['unit'] ?? '').toString().isEmpty,
                            ),
                          ),
                        ),
                        DataCell(number(g, 'baseline', () => widget.edit(g))),
                        DataCell(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              number(g, 'current', () => widget.measure(g)),
                              if (object(g['measurement'])['pending'] == true)
                                const Text(
                                  'На устройстве',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xff8c6e3c),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        DataCell(number(g, 'target', () => widget.edit(g))),
                        DataCell(
                          SizedBox(
                            width: 140,
                            child: g['delta'] is num
                                ? Text(
                                    '${g['delta'] > 0 ? '+' : ''}${goalNumber(g['delta'])}${g['lastChange'] is num ? '\nК прошлому: ${g['lastChange'] > 0 ? '+' : ''}${goalNumber(g['lastChange'])}' : ''}',
                                  )
                                : editable(
                                    'Заполнить',
                                    () => fillProgress(g),
                                    missing: true,
                                  ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 150,
                            child: g['percent'] is num
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                : Tooltip(
                                    message: 'Для расчёта нужны исходное значение, замер и отличающийся ориентир',
                                    child: editable(
                                      'Заполнить',
                                      () => fillProgress(g),
                                      missing: true,
                                    ),
                                  ),
                          ),
                        ),
                        DataCell(
                          editable(
                            object(g['measurement'])['date']?.toString() ??
                                'Заполнить',
                            () => object(g['measurement'])['date'] == null
                                ? widget.measure(g)
                                : widget.history(g),
                          ),
                        ),
                        DataCell(
                          editable(
                            (g['dueDate'] ?? '').toString().isEmpty
                                ? 'Заполнить'
                                : g['dueDate'].toString(),
                            () => widget.edit(g),
                          ),
                        ),
                        DataCell(
                          editable(switch (g['status']) {
                            'active' => 'Активная',
                            'paused' => 'На паузе',
                            'archived' => 'В архиве',
                            _ => 'Заполнить',
                          }, () => widget.edit(g)),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
