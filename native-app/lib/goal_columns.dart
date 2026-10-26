import 'package:flutter/material.dart';

import 'domain.dart';
import 'forms.dart';
import 'inline_cell.dart';
import 'repository.dart';

Future<void> editGoalColumn(
  BuildContext context,
  DashboardRepository repo, {
  Json? column,
}) async {
  final id = column?['id']?.toString() ?? uuid.v4();
  final key = 'goalColumnComposer:${repo.serverId}:$id';
  final old = object(repo.local.get(key));
  final base = column ?? {'id': id, 'title': '', 'type': 'text'};
  await editFields(
    context,
    title: column == null ? 'Новый столбец' : 'Название столбца',
    initial: {...base, ...old},
    fields: [
      const FieldSpec('title', 'Название'),
      if (column == null)
        const FieldSpec(
          'type',
          'Тип значения',
          options: {
            'text': 'Текст',
            'number': 'Число',
            'date': 'Дата',
            'checkbox': 'Галочка',
            'select': 'Список',
          },
        ),
      if (column == null)
        const FieldSpec(
          'choices',
          'Варианты списка · каждый с новой строки',
          lines: 4,
        ),
    ],
    draft: (input) => repo.local.set(key, input),
    save: (input) async {
      final title = input['title'].toString();
      if (title.trim().isEmpty || title.length > 120) {
        throw const FormatException('Название: 1–120 символов.');
      }
      if (repo
          .goalColumns(archived: true)
          .any(
            (c) =>
                c['id'] != id &&
                c['title'].toString().trim().toLowerCase() ==
                    title.trim().toLowerCase(),
          )) {
        throw const FormatException('Столбец с таким названием уже есть.');
      }
      final type = input['type']?.toString() ?? 'text';
      final options = {
        for (final text
            in (input['choices'] ?? '')
                .toString()
                .split('\n')
                .where((s) => s.trim().isNotEmpty))
          text: text,
      };
      if (column == null &&
          type == 'select' &&
          (options.isEmpty ||
              options.length > 100 ||
              options.keys.any((s) => s.length > 120))) {
        throw const FormatException(
          'Задай 1–100 вариантов, до 120 символов каждый.',
        );
      }
      repo.goalGridCommand(
        column == null ? 'createGoalColumn' : 'updateGoalColumn',
        {
          'id': id,
          'title': title,
          if (column == null) ...{
            'type': type,
            if (type == 'select') 'options': options,
          } else
            'expectedRevision': column['revision'] ?? 0,
        },
      );
      repo.local.remove(key);
    },
  );
}

class GoalCustomCell extends StatelessWidget {
  final DashboardRepository repo;
  final Json goal, column;
  const GoalCustomCell({
    super.key,
    required this.repo,
    required this.goal,
    required this.column,
  });
  @override
  Widget build(BuildContext context) {
    final id = column['id'].toString(),
        current = object(goal['customValues'])[column['id']];
    void save(dynamic value, dynamic before) =>
        repo.editGoalCell(goal['id'].toString(), id, before, value);
    void choose(dynamic value) {
      try {
        save(value, current);
      } catch (error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }

    if (column['type'] == 'checkbox') {
      return Checkbox(
        tristate: true,
        value: current as bool?,
        onChanged: choose,
      );
    }
    if (column['type'] == 'select') {
      return DropdownButtonFormField<String>(
        key: ValueKey('goal-custom-select:${goal['id']}:$id:$current'),
        initialValue: current as String?,
        isExpanded: true,
        itemHeight: null,
        decoration: const InputDecoration(isDense: true, hintText: 'Заполнить'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Очистить')),
          for (final option in object(column['options']).entries)
            DropdownMenuItem(
              value: option.key,
              child: Text(option.value.toString()),
            ),
        ],
        onChanged: (value) => choose(value?.isEmpty == true ? null : value),
      );
    }
    final key = 'goalCustom:${repo.serverId}:${goal['id']}:$id';
    return InlineCell(
      key: ValueKey('goal-custom:${goal['id']}:$id'),
      text: current?.toString() ?? '',
      label: column['title'].toString(),
      maxLines: column['type'] == 'text' ? 3 : 1,
      draft: object(repo.local.get(key))['text'] as String?,
      begin: () {
        if (repo.local.get(key) == null) {
          repo.local.set(key, {
            'text': current?.toString() ?? '',
            'before': current,
          });
        }
      },
      retain: (text) =>
          repo.local.set(key, {...object(repo.local.get(key)), 'text': text}),
      cancel: () => repo.local.remove(key),
      commit: (text) async {
        dynamic value = text.isEmpty ? null : text;
        if (column['type'] == 'number' && text.isNotEmpty) {
          value = num.tryParse(text.replaceAll(',', '.'));
          if (value is! num || !value.isFinite) {
            throw const FormatException('Укажи конечное число.');
          }
        }
        if (column['type'] == 'date' &&
            text.isNotEmpty &&
            DateTime.tryParse(text)?.toIso8601String().substring(0, 10) !=
                text) {
          throw const FormatException('Дата: ГГГГ-ММ-ДД.');
        }
        if (column['type'] == 'text' && text.length > 10000) {
          throw const FormatException('Текст до 10000 символов.');
        }
        save(value, object(repo.local.get(key))['before']);
        repo.local.remove(key);
      },
    );
  }
}
