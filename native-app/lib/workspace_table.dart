import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'model_hierarchy.dart';
import 'repository.dart';
import 'forms.dart';

class WorkColumn {
  final String id, title;
  final double width;
  final String? hint;
  const WorkColumn(this.id, this.title, {this.width = 160, this.hint});
}

/// Search keeps ancestors; sorting changes sibling presentation only. WBS remains
/// the path of the original hierarchy, never a new stored order.
List<Json> arrangeTableRows(
  List<Json> source,
  Json view,
  dynamic Function(Json, String) value,
  Set<String> collapsed,
) {
  final original = [
    for (final row in hierarchyRows(source))
      {...row, if (row['_sourceWbs'] != null) '_wbs': row['_sourceWbs']},
  ];
  final map = {for (final row in original) row['id'].toString(): row};
  final indexes = {
    for (var i = 0; i < original.length; i++) original[i]['id']: i,
  };
  final query = (view['query'] ?? '').toString().toLowerCase();
  final allowed = <String>{};
  for (final row in original) {
    if (query.isNotEmpty &&
        !value(row, '*').toString().toLowerCase().contains(query)) {
      continue;
    }
    String? id = row['id'].toString();
    final seen = <String>{};
    while (id != null && seen.add(id) && map.containsKey(id)) {
      allowed.add(id);
      id = parentOf(map[id]!);
    }
  }
  final sort = view['sort']?.toString(), group = view['group']?.toString();
  final descending = view['descending'] == true;
  int compare(Json a, Json b) {
    if (sort == null || sort.isEmpty) {
      return indexes[a['id']]!.compareTo(indexes[b['id']]!);
    }
    final av = value(a, sort), bv = value(b, sort);
    final order = av is num && bv is num
        ? av.compareTo(bv)
        : (av ?? '').toString().toLowerCase().compareTo(
            (bv ?? '').toString().toLowerCase(),
          );
    return order == 0
        ? indexes[a['id']]!.compareTo(indexes[b['id']]!)
        : descending
        ? -order
        : order;
  }

  final result = <Json>[], seen = <String>{};
  void visit(Json row, {bool root = false}) {
    final id = row['id'].toString();
    if (!allowed.contains(id) || !seen.add(id)) return;
    result.add({
      ...row,
      if (root && group != null && group.isNotEmpty)
        '_viewGroup': (value(row, group) ?? 'Не заполнено').toString(),
    });
    if (collapsed.contains(id) && query.isEmpty) return;
    final children = original.where((r) => parentOf(r) == id).toList();
    if (sort != null && sort.isNotEmpty) children.sort(compare);
    for (final child in children) {
      visit(child);
    }
  }

  final roots = original.where((r) => r['_depth'] == 0).toList();
  roots.sort((a, b) {
    final grouped = group == null || group.isEmpty
        ? 0
        : (value(a, group) ?? '').toString().compareTo(
            (value(b, group) ?? '').toString(),
          );
    return grouped != 0 ? grouped : compare(a, b);
  });
  for (final row in roots) {
    visit(row, root: true);
  }
  return result;
}

class WorkspaceTable extends StatefulWidget {
  final DashboardRepository repo;
  final String viewKey;
  final List<WorkColumn> columns;
  final List<Json> items;
  final Set<String> collapsed;
  final Widget Function(BuildContext, Json, WorkColumn) cell;
  final dynamic Function(Json, String) value;
  final String Function(Json)? rowKey;
  final bool grouping;
  final List<Widget> tools;
  final bool compactToolbar;
  final VoidCallback? reset;
  final Future<void> Function(WorkColumn)? rename;
  final VoidCallback? addColumn;
  final Future<void> Function(WorkColumn)? removeColumn;
  final bool Function(WorkColumn)? canRemoveColumn;
  final bool cleanGrid;
  final Widget Function(Json, Widget, ValueChanged<Offset>)? rowWrapper;
  final bool rowDragging;
  const WorkspaceTable({
    super.key,
    required this.repo,
    required this.viewKey,
    required this.columns,
    required this.items,
    required this.cell,
    required this.value,
    this.collapsed = const {},
    this.rowKey,
    this.grouping = true,
    this.tools = const [],
    this.compactToolbar = false,
    this.reset,
    this.rename,
    this.addColumn,
    this.removeColumn,
    this.canRemoveColumn,
    this.cleanGrid = false,
    this.rowWrapper,
    this.rowDragging = false,
  });
  @override
  State<WorkspaceTable> createState() => _WorkspaceTableState();
}

class _WorkspaceTableState extends State<WorkspaceTable> {
  final vertical = ScrollController();
  final scrolls = <String, ScrollController>{};
  late final TextEditingController query;
  bool scrolling = false;
  double offset = 0;
  final viewportKey = GlobalKey();
  Offset? dragPosition;
  Timer? dragScroll;
  void dragHover(Offset position) {
    dragPosition = position;
    dragScroll ??= Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!widget.rowDragging || !mounted) {
        dragScroll?.cancel();
        dragScroll = null;
        return;
      }
      final box = viewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || dragPosition == null || !vertical.hasClients) return;
      final y = box.globalToLocal(dragPosition!).dy;
      final delta = y < 48
          ? -12.0
          : y > box.size.height - 48
          ? 12.0
          : 0.0;
      if (delta != 0) {
        vertical.jumpTo(
          (vertical.offset + delta).clamp(0, vertical.position.maxScrollExtent),
        );
      }
    });
  }

  Json get view => object(widget.repo.local.get(widget.viewKey));
  @override
  void initState() {
    super.initState();
    query = TextEditingController(text: (view['query'] ?? '').toString());
  }

  void change(Json patch) {
    widget.repo.local.set(widget.viewKey, {...view, ...patch});
    setState(() {});
  }

  ScrollController horizontal(String id) => scrolls.putIfAbsent(id, () {
    final c = ScrollController(initialScrollOffset: offset);
    c.addListener(() {
      if (scrolling || !c.hasClients) return;
      offset = c.offset;
      scrolling = true;
      for (final other in scrolls.values) {
        if (other != c && other.hasClients) {
          other.jumpTo(offset.clamp(0, other.position.maxScrollExtent));
        }
      }
      scrolling = false;
    });
    return c;
  });
  List<WorkColumn> get columns {
    final all = widget.columns;
    if (all.isEmpty) return [];
    final order = (view['order'] as List? ?? [])
        .whereType<String>()
        .toSet()
        .toList();
    return [
      ...[...order, ...all.map((c) => c.id).where((id) => !order.contains(id))]
          .map((id) => all.where((c) => c.id == id).firstOrNull)
          .whereType<WorkColumn>()
          .map(
            (c) => widget.rename != null
                ? c
                : WorkColumn(
                    c.id,
                    (object(view['labels'])[c.id] ?? c.title).toString(),
                    width: c.width,
                    hint: c.hint,
                  ),
          ),
    ];
  }

  double width(WorkColumn col) =>
      (object(view['widths'])[col.id] as num? ?? col.width).toDouble().clamp(
        100,
        600,
      );
  Future<void> renameColumn(WorkColumn column) async {
    if (widget.rename != null) {
      await widget.rename!(column);
      return;
    }
    await editFields(
      context,
      title: 'Название столбца',
      initial: {'title': column.title},
      fields: const [FieldSpec('title', 'Название')],
      save: (input) async {
        final title = input['title'].toString();
        if (title.trim().isEmpty || title.length > 120) {
          throw const FormatException('Название: 1–120 символов.');
        }
        change({
          'labels': {...object(view['labels']), column.id: title},
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.cleanGrid) return buildTable(context);
    final outer = Theme.of(context), dark = outer.brightness == Brightness.dark;
    final panel = dark ? const Color(0xff202225) : Colors.white;
    final head = dark ? const Color(0xff292d31) : const Color(0xfff5f6f7);
    final line = dark ? const Color(0xff3d4146) : const Color(0xffe3e6e8);
    final text = dark ? const Color(0xffecedef) : const Color(0xff252a2e);
    final label = dark ? const Color(0xffb6bcc2) : const Color(0xff646c74);
    final clean = outer.copyWith(
      colorScheme: outer.colorScheme.copyWith(
        surface: panel,
        surfaceContainer: panel,
        surfaceContainerLow: panel,
        surfaceContainerHigh: head,
        surfaceContainerHighest: dark
            ? const Color(0xff3b4046)
            : const Color(0xffeef0f1),
        secondaryContainer: dark
            ? const Color(0xff30383d)
            : const Color(0xffeef2f4),
        onSurface: text,
        onSurfaceVariant: label,
        outlineVariant: line,
      ),
      cardTheme: outer.cardTheme.copyWith(color: panel),
      dividerColor: line,
      iconTheme: outer.iconTheme.copyWith(color: label),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: text,
          disabledForegroundColor: label.withValues(alpha: .55),
          textStyle: outer.textTheme.bodyMedium,
        ),
      ),
      inputDecorationTheme: outer.inputDecorationTheme.copyWith(
        fillColor: panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: line),
        ),
      ),
    );
    return Theme(
      data: clean,
      child: Builder(builder: buildTable),
    );
  }

  Widget buildTable(BuildContext context) {
    final cols = columns;
    if (cols.isEmpty) return const SizedBox.shrink();
    final shown = arrangeTableRows(
      widget.items,
      {...view, if (!widget.grouping) 'group': ''},
      widget.value,
      widget.collapsed,
    );
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final toolbar = <Widget>[
      SizedBox(
        width: 240 * scale,
        child: TextField(
          controller: query,
          decoration: const InputDecoration(
            labelText: 'Поиск по таблице',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (s) => change({'query': s}),
        ),
      ),
      if (widget.addColumn != null)
        OutlinedButton.icon(
          key: const ValueKey('table-add-column'),
          onPressed: widget.addColumn,
          icon: const Icon(Icons.add),
          label: const Text('Столбец'),
        ),
      ...widget.tools,
      if (widget.rowWrapper != null &&
          (view['sort'] ?? '').toString().isNotEmpty)
        TextButton.icon(
          key: const ValueKey('table-manual-order'),
          onPressed: () =>
              change({'sort': null, 'descending': false, 'group': ''}),
          icon: const Icon(Icons.swap_vert),
          label: const Text('Порядок строк'),
        ),
      if (widget.grouping)
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            initialValue: widget.columns.any((c) => c.id == view['group'])
                ? view['group'].toString()
                : '',
            key: ValueKey('group:${view['group']}'),
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Группировать верхние уровни',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Без группировки')),
              for (final c in widget.columns.where((c) => c.id != '_actions'))
                DropdownMenuItem(value: c.id, child: Text(c.title)),
            ],
            onChanged: (value) => change({'group': value}),
          ),
        ),
      TextButton(
        onPressed: () {
          query.clear();
          change({'query': '', 'sort': '', 'group': '', 'descending': false});
          widget.reset?.call();
        },
        child: const Text('Сбросить'),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.compactToolbar)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final tool in toolbar)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: tool,
                  ),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: toolbar,
          ),
        const SizedBox(height: 8),
        if (!widget.compactToolbar)
          Text(
            'Показано: ${shown.length} / ${widget.items.length} · перетащи заголовок для перестановки, границу — для ширины · нажатие — сортировка',
          ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            final unpinned = widget.cleanGrid && box.maxWidth < 560;
            double cellWidth(WorkColumn col) =>
                unpinned && col.id == cols.first.id
                ? min(width(col), max(280.0, box.maxWidth))
                : width(col);
            final pinned = min(
              width(cols.first),
              max(130.0, box.maxWidth * .48),
            );
            Widget line(String id, Json? row) {
              final head = row == null;
              Widget content(WorkColumn col, double w) => SizedBox(
                key: ValueKey('column-cell:${col.id}'),
                width: w,
                child: DecoratedBox(
                  decoration: widget.cleanGrid && col.id != cols.first.id
                      ? BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                        )
                      : const BoxDecoration(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: head
                        ? Row(
                            children: [
                              Expanded(
                                child: DragTarget<String>(
                                  onWillAcceptWithDetails: (d) =>
                                      d.data != col.id &&
                                      cols.any((c) => c.id == d.data),
                                  onAcceptWithDetails: (d) {
                                    final order = cols
                                        .map((c) => c.id)
                                        .toList();
                                    final from = order.indexOf(d.data),
                                        to = order.indexOf(col.id);
                                    order.removeAt(from);
                                    order.insert(to, d.data);
                                    change({'order': order});
                                  },
                                  builder: (context, candidate, rejected) =>
                                      Draggable<String>(
                                        key: ValueKey('column-drag:${col.id}'),
                                        data: col.id,
                                        affinity: Axis.horizontal,
                                        feedback: Material(
                                          elevation: 4,
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Text(col.title),
                                          ),
                                        ),
                                        childWhenDragging: Opacity(
                                          opacity: .4,
                                          child: Text(col.title),
                                        ),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            border: candidate.isEmpty
                                                ? null
                                                : Border(
                                                    left: BorderSide(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                      width: 2,
                                                    ),
                                                  ),
                                          ),
                                          child: TextButton(
                                            style: widget.cleanGrid
                                                ? TextButton.styleFrom(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 4,
                                                          vertical: 8,
                                                        ),
                                                    foregroundColor:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                  )
                                                : null,
                                            onPressed: () => change({
                                              'sort': col.id,
                                              'descending':
                                                  view['sort'] == col.id &&
                                                  view['descending'] != true,
                                            }),
                                            child: Tooltip(
                                              message: col.hint ?? col.title,
                                              child: Text(
                                                '${col.title}${view['sort'] == col.id
                                                    ? view['descending'] == true
                                                          ? ' ↓'
                                                          : ' ↑'
                                                    : ''}',
                                                softWrap: true,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                              IconButton(
                                key: ValueKey('column-rename:${col.id}'),
                                tooltip: 'Переименовать столбец «${col.title}»',
                                onPressed: () => renameColumn(col),
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 40,
                                ),
                                padding: const EdgeInsets.all(4),
                                icon: const Icon(Icons.edit_outlined, size: 16),
                              ),
                              if (widget.removeColumn != null)
                                PopupMenuButton<String>(
                                  key: ValueKey('column-menu:${col.id}'),
                                  tooltip: 'Меню столбца',
                                  child: const SizedBox(
                                    width: 28,
                                    height: 40,
                                    child: Icon(Icons.more_vert, size: 16),
                                  ),
                                  onSelected: (action) {
                                    if (action == 'rename') renameColumn(col);
                                    if (action == 'remove') {
                                      widget.removeColumn!(col);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Переименовать'),
                                    ),
                                    PopupMenuItem(
                                      key: ValueKey('column-remove:${col.id}'),
                                      value: 'remove',
                                      enabled:
                                          widget.canRemoveColumn?.call(col) ??
                                          true,
                                      child: const Text('Убрать столбец'),
                                    ),
                                  ],
                                ),
                              Semantics(
                                label: 'Изменить ширину: ${col.title}',
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.resizeColumn,
                                  child: GestureDetector(
                                    key: ValueKey('column-resize:${col.id}'),
                                    behavior: HitTestBehavior.opaque,
                                    onHorizontalDragUpdate: (event) => change({
                                      'widths': {
                                        ...object(view['widths']),
                                        col.id: (width(col) + event.delta.dx)
                                            .clamp(100, 600),
                                      },
                                    }),
                                    child: SizedBox(
                                      width: 12,
                                      height: 48,
                                      child: Center(
                                        child: Container(
                                          width: 1,
                                          height: 28,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outlineVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Semantics(
                            label: col.title,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: widget.cell(context, row, col),
                            ),
                          ),
                  ),
                ),
              );
              return Container(
                key: row == null
                    ? const ValueKey('workspace-sticky-header')
                    : ValueKey(
                        widget.rowKey?.call(row) ??
                            'workspace-row:${row['id']}',
                      ),
                decoration: BoxDecoration(
                  color: head
                      ? Theme.of(context).colorScheme.surfaceContainerHigh
                      : widget.repo.local.get('${widget.viewKey}:selection') ==
                            row['id']
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : row['_depth'] == 0
                      ? Theme.of(context).colorScheme.surfaceContainer
                      : Theme.of(context).cardTheme.color,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: Listener(
                  onPointerDown: head
                      ? null
                      : (_) {
                          if (widget.repo.local.get(
                                '${widget.viewKey}:selection',
                              ) ==
                              row['id']) {
                            return;
                          }
                          widget.repo.local.set(
                            '${widget.viewKey}:selection',
                            row['id'],
                          );
                          setState(() {});
                        },
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!unpinned) content(cols.first, pinned),
                        if (!unpinned) const VerticalDivider(width: 1),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: horizontal(id),
                            primary: false,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final col in cols.skip(unpinned ? 0 : 1))
                                  content(col, cellWidth(col)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            String? previousGroup;
            final lines = <Widget>[];
            for (final row in shown) {
              if (row['_viewGroup'] != null &&
                  previousGroup != row['_viewGroup']) {
                previousGroup = row['_viewGroup'].toString();
                lines.add(
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      previousGroup,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              }
              final content = line(row['id'].toString(), row);
              lines.add(
                widget.rowWrapper?.call(row, content, dragHover) ?? content,
              );
            }
            final tableHeight = min(
              600.0 * min(scale, 1.4),
              max(140.0, shown.length * 82.0 * scale + 20),
            );
            final bodyViewport = Scrollbar(
              key: viewportKey,
              controller: vertical,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: vertical,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: lines,
                ),
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                line('_header', null),
                if (widget.cleanGrid)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 600.0 * min(scale, 1.4),
                    ),
                    child: bodyViewport,
                  )
                else
                  SizedBox(height: tableHeight, child: bodyViewport),
                Scrollbar(
                  controller: horizontal('_footer'),
                  thumbVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: SingleChildScrollView(
                    controller: horizontal('_footer'),
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: max(
                        box.maxWidth,
                        cols
                                .skip(unpinned ? 0 : 1)
                                .fold<double>(
                                  0,
                                  (sum, col) => sum + cellWidth(col),
                                ) +
                            (unpinned ? 0 : pinned),
                      ),
                      height: 20,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    dragScroll?.cancel();
    query.dispose();
    vertical.dispose();
    for (final c in scrolls.values) {
      c.dispose();
    }
    super.dispose();
  }
}
