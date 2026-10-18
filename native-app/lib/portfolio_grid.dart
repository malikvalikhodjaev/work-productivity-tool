import 'package:flutter/material.dart';

import 'domain.dart';
import 'repository.dart';

const gridTypes = {
  'text': 'Текст',
  'number': 'Число',
  'date': 'Дата',
  'select': 'Список вариантов',
  'checkbox': 'Галочка',
  'computed': 'Рассчитывается',
};
dynamic gridValue(Json row, Json col) {
  if (col['custom'] == true) return object(row['customValues'])[col['id']];
  final summary = object(row['summary']);
  if (col['id'] == '_slots') {
    return '${summary['filled'] ?? 0} / ${summary['slots'] ?? 0}';
  }
  if (col['id'] == '_gaps') {
    return summary['totalZones'] == null
        ? null
        : '${summary['gaps']} / ${summary['totalZones']}';
  }
  return row[col['id']];
}

String gridText(Json row, Json col) {
  final value = gridValue(row, col);
  if (value == null || value == '') return 'No Data';
  if (col['type'] == 'checkbox') return value == true ? '✓' : '—';
  return (object(col['options'])[value] ?? value).toString();
}

class PortfolioGrid extends StatefulWidget {
  final DashboardRepository repo;
  final String table;
  final List<Json> items;
  final Future<void> Function() addRow;
  final void Function(Json) openRow;
  const PortfolioGrid({
    super.key,
    required this.repo,
    required this.table,
    required this.items,
    required this.addRow,
    required this.openRow,
  });
  @override
  State<PortfolioGrid> createState() => _PortfolioGridState();
}

class _PortfolioGridState extends State<PortfolioGrid> {
  DashboardRepository get repo => widget.repo;
  String get viewKey => 'gridView:${repo.serverId}:${widget.table}';
  Json get view => object(repo.local.get(viewKey));
  List<Json> get columns => repo.gridColumns(widget.table);
  List<Json> visible() {
    final prefs = view, all = columns;
    final saved = (prefs['order'] as List? ?? []).cast<String>();
    final hidden = (prefs['hidden'] as List? ?? []).cast<String>();
    final ordered = [
      ...saved,
      ...all.map((c) => c['id'].toString()).where((id) => !saved.contains(id)),
    ];
    final result = <Json>[];
    for (final id in ordered) {
      final col = all.where((c) => c['id'] == id).firstOrNull;
      if (col != null &&
          !hidden.contains(id) &&
          (saved.contains(id) ||
              col['visible'] == true ||
              col['custom'] == true)) {
        result.add({
          ...col,
          'title': object(prefs['labels'])[id] ?? col['title'],
        });
      }
    }
    return result.isEmpty && all.isNotEmpty ? [all.first] : result;
  }

  void preference(Json values) {
    repo.local.set(viewKey, {...view, ...values});
    setState(() {});
  }

  void error(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> cell(Json row, Json col) async {
    final key =
        'gridCellDraft:${repo.serverId}:${widget.table}:${row['id']}:${col['id']}';
    final draft = repo.local.get(key);
    final before = draft is Map ? draft['before'] : gridValue(row, col);
    dynamic value = draft is Map ? draft['value'] : before;
    final controller = TextEditingController(text: value?.toString() ?? '');
    String? message;
    void retain() {
      repo.local.set(key, {'before': before, 'value': value});
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(col['title'].toString()),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    (row['name'] ?? row['uniqueName'] ?? row['typeName'] ?? '')
                        .toString(),
                  ),
                  const SizedBox(height: 16),
                  if (col['type'] == 'select' || col['type'] == 'checkbox')
                    DropdownButtonFormField<String>(
                      initialValue: value?.toString() ?? '',
                      isExpanded: true,
                      items: [
                        if (col['custom'] == true || col['type'] == 'checkbox')
                          const DropdownMenuItem(
                            value: '',
                            child: Text('No Data'),
                          ),
                        for (final item
                            in (col['type'] == 'checkbox'
                                    ? {'true': 'Да', 'false': 'Нет'}
                                    : object(col['options']))
                                .entries)
                          DropdownMenuItem(
                            value: item.key,
                            child: Text(item.value.toString()),
                          ),
                      ],
                      onChanged: (v) {
                        value = v == ''
                            ? null
                            : col['type'] == 'checkbox'
                            ? v == 'true'
                            : v;
                        retain();
                      },
                    )
                  else
                    TextField(
                      controller: controller,
                      autofocus: true,
                      maxLines: col['type'] == 'text' ? 8 : 1,
                      minLines: col['type'] == 'text' ? 3 : 1,
                      maxLength: col['type'] == 'text'
                          ? (col['maxLength'] as int? ?? 10000)
                          : null,
                      keyboardType: col['type'] == 'number'
                          ? const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            )
                          : TextInputType.multiline,
                      decoration: InputDecoration(
                        labelText: col['type'] == 'date'
                            ? 'Дата · ГГГГ-ММ-ДД'
                            : col['title'].toString(),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        value = v;
                        retain();
                      },
                    ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Закрыть'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  dynamic result = value;
                  if (col['type'] == 'text' && result == null) result = '';
                  if (col['type'] == 'number') {
                    result = (value?.toString() ?? '').isEmpty
                        ? null
                        : num.tryParse(value.toString().replaceAll(',', '.'));
                    if (value != null &&
                        value != '' &&
                        (result == null || !(result as num).isFinite)) {
                      throw const FormatException('Укажи число.');
                    }
                  }
                  if (col['type'] == 'date') {
                    result = (value?.toString() ?? '').isEmpty ? null : value;
                    if (result != null &&
                        (DateTime.tryParse(result.toString())
                                ?.toIso8601String()
                                .substring(0, 10) !=
                            result)) {
                      throw const FormatException('Дата в формате ГГГГ-ММ-ДД.');
                    }
                  }
                  if (col['required'] == true &&
                      (result == null || result.toString().trim().isEmpty)) {
                    throw const FormatException('Заполни значение.');
                  }
                  repo.gridCommand('editCells', {
                    'table': widget.table,
                    'id': row['id'],
                    'changes': [
                      {
                        'columnId': col['id'],
                        'before': before,
                        'value': result,
                      },
                    ],
                  });
                  repo.local.remove(key);
                  Navigator.pop(dialogContext);
                } catch (e) {
                  setDialog(() => message = e.toString());
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    // The route may still animate out while its controller is being read.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  void rowCard(Json row) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          (row['name'] ?? row['uniqueName'] ?? row['typeName'] ?? 'Строка')
              .toString(),
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final col in columns)
                  ListTile(
                    title: Text(col['title'].toString()),
                    subtitle: Text(gridText(row, col)),
                    trailing: col['type'] == 'computed'
                        ? null
                        : const Icon(Icons.edit_outlined),
                    onTap: col['type'] == 'computed'
                        ? null
                        : () {
                            Navigator.pop(dialogContext);
                            cell(row, col);
                          },
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> configure([Json? column]) async {
    final title = TextEditingController(
      text: column == null
          ? ''
          : (object(view['labels'])[column['id']] ?? column['title'])
                .toString(),
    );
    final options = TextEditingController();
    String type = 'text';
    String? message;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(column == null ? 'Новый столбец' : 'Настроить столбец'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    autofocus: true,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Название столбца',
                    ),
                  ),
                  if (column == null)
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      items: [
                        for (final item in gridTypes.entries.where(
                          (e) => e.key != 'computed',
                        ))
                          DropdownMenuItem(
                            value: item.key,
                            child: Text(item.value),
                          ),
                      ],
                      onChanged: (v) => setDialog(() => type = v!),
                    )
                  else
                    Text(
                      'Тип: ${gridTypes[column['type']]} · сохраняется, чтобы не потерять значения.',
                    ),
                  if (column == null && type == 'select')
                    TextField(
                      controller: options,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Варианты · каждый с новой строки',
                      ),
                    ),
                  if (column != null)
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: () => move(column, -1),
                          child: const Text('← Левее'),
                        ),
                        TextButton(
                          onPressed: () => move(column, 1),
                          child: const Text('Правее →'),
                        ),
                        TextButton(
                          onPressed: () {
                            preference({
                              'hidden': [
                                ...(view['hidden'] as List? ?? []),
                                column['id'],
                              ],
                            });
                            Navigator.pop(dialogContext);
                          },
                          child: const Text('Скрыть'),
                        ),
                        if (column['custom'] == true)
                          TextButton(
                            onPressed: () {
                              try {
                                repo.gridCommand('updateColumn', {
                                  'table': widget.table,
                                  'id': column['id'],
                                  'expectedRevision': column['revision'],
                                  'archived': true,
                                });
                                Navigator.pop(dialogContext);
                              } catch (e) {
                                setDialog(() => message = e.toString());
                              }
                            },
                            child: const Text('В архив столбцов'),
                          ),
                      ],
                    ),
                  if (message != null) Text(message!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Закрыть'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  if (title.text.trim().isEmpty) {
                    throw const FormatException('Назови столбец.');
                  }
                  if (column == null) {
                    final choices = {
                      for (final line
                          in options.text
                              .split('\n')
                              .map((s) => s.trim())
                              .where((s) => s.isNotEmpty))
                        line: line,
                    };
                    if (type == 'select' && choices.isEmpty) {
                      throw const FormatException('Добавь варианты списка.');
                    }
                    repo.gridCommand('createColumn', {
                      'table': widget.table,
                      'id': uuid.v4(),
                      'title': title.text,
                      'type': type,
                      if (type == 'select') 'options': choices,
                    });
                  } else if (column['custom'] == true) {
                    repo.gridCommand('updateColumn', {
                      'table': widget.table,
                      'id': column['id'],
                      'expectedRevision': column['revision'],
                      'title': title.text,
                    });
                  } else {
                    preference({
                      'labels': {
                        ...object(view['labels']),
                        column['id']: title.text,
                      },
                    });
                  }
                  Navigator.pop(dialogContext);
                } catch (e) {
                  setDialog(() => message = e.toString());
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    title.dispose();
    options.dispose();
  }

  void move(Json column, int delta) {
    final order = visible().map((c) => c['id']).toList(),
        i = visible().indexWhere((c) => c['id'] == column['id']),
        j = visible().indexWhere((c) => c['id'] == column['id']) + delta;
    if (i < 0 || j < 0 || j >= order.length) return;
    final old = order[i];
    order[i] = order[j];
    order[j] = old;
    preference({'order': order});
  }

  void chooseColumns() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Столбцы'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Видимость, порядок и имена стандартных полей сохраняются на этом устройстве. Свои столбцы синхронизируются.',
                  ),
                  for (final column in repo.gridColumns(
                    widget.table,
                    archived: true,
                  ))
                    ListTile(
                      title: Text(
                        (object(view['labels'])[column['id']] ??
                                column['title'])
                            .toString(),
                      ),
                      leading: Checkbox(
                        value: visible().any((c) => c['id'] == column['id']),
                        onChanged: column['archived'] == true
                            ? null
                            : (checked) {
                                final hidden = [
                                      ...(view['hidden'] as List? ?? []),
                                    ],
                                    order = [...visible().map((c) => c['id'])];
                                if (checked == true) {
                                  hidden.remove(column['id']);
                                  if (!order.contains(column['id'])) {
                                    order.add(column['id']);
                                  }
                                } else {
                                  hidden.add(column['id']);
                                }
                                preference({'hidden': hidden, 'order': order});
                                setDialog(() {});
                              },
                      ),
                      trailing: TextButton(
                        onPressed: () {
                          if (column['archived'] == true) {
                            try {
                              repo.gridCommand('updateColumn', {
                                'table': widget.table,
                                'id': column['id'],
                                'expectedRevision': column['revision'],
                                'archived': false,
                              });
                              setDialog(() {});
                            } catch (e) {
                              error(e);
                            }
                          } else {
                            Navigator.pop(dialogContext);
                            configure(column);
                          }
                        },
                        child: Text(
                          column['archived'] == true
                              ? 'Восстановить'
                              : 'Настроить',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Готово'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cols = visible();
    if (cols.isEmpty) return const Text('Подключи обновлённый сервер таблиц.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Ячейка — изменить · ↗ — открыть строку'),
            Wrap(
              children: [
                TextButton(
                  onPressed: chooseColumns,
                  child: const Text('Столбцы'),
                ),
                TextButton.icon(
                  onPressed: configure,
                  icon: const Icon(Icons.add),
                  label: const Text('Столбец'),
                ),
                TextButton.icon(
                  onPressed: widget.addRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Строка'),
                ),
              ],
            ),
          ],
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 20,
              horizontalMargin: 12,
              dataRowMinHeight: 54,
              dataRowMaxHeight: 100,
              columns: [
                const DataColumn(label: Text('')),
                for (final c in cols)
                  DataColumn(
                    label: TextButton(
                      onPressed: () => configure(c),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c['title'].toString()),
                          Text(
                            gridTypes[c['type']] ?? '',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                const DataColumn(label: Text('')),
              ],
              rows: [
                for (final row in widget.items)
                  DataRow(
                    key: ValueKey('grid:${widget.table}:${row['id']}'),
                    cells: [
                      DataCell(
                        IconButton(
                          tooltip: 'Открыть строку',
                          onPressed: () => rowCard(row),
                          icon: const Icon(Icons.open_in_full, size: 18),
                        ),
                      ),
                      for (final c in cols)
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 110,
                              maxWidth: 250,
                            ),
                            child: Text(
                              gridText(row, c),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          onTap: c['type'] == 'computed'
                              ? null
                              : () => cell(row, c),
                        ),
                      DataCell(
                        TextButton(
                          onPressed: () => widget.openRow(row),
                          child: Text(
                            widget.table == 'projects'
                                ? 'Открыть моделер'
                                : 'Карточка альфы',
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (widget.items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No Data · добавь первую строку.'),
          ),
      ],
    );
  }
}
