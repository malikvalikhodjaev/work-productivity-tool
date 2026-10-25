import 'package:flutter/material.dart';

import 'time_types.dart';

class TimeTypePicker extends StatelessWidget {
  final String value, label, emptyLabel;
  final ValueChanged<String> onChanged;
  final bool enabled;
  const TimeTypePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Типы времени',
    this.emptyLabel = 'Не выбран',
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) {
    final selected = timeTypes(value);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: selected.isEmpty
            ? emptyLabel
            : 'Можно выбрать несколько типов',
        helperMaxLines: 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (value.isNotEmpty && selected.isEmpty)
            Text('Прежнее значение: $value'),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final entry in timeTypeLabels.entries.where(
                (e) => e.key != 'unclassified',
              ))
                FilterChip(
                  key: ValueKey('time-type:${entry.key}'),
                  label: Text(entry.value),
                  selected: selected.contains(entry.key),
                  onSelected: !enabled
                      ? null
                      : (checked) {
                          final next = selected.toSet();
                          if (checked) {
                            next.add(entry.key);
                          } else {
                            next.remove(entry.key);
                          }
                          onChanged(encodeTimeTypes(next));
                        },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
