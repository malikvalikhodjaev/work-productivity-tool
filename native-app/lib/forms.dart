import 'package:flutter/material.dart';

import 'domain.dart';

class FieldSpec {
  final String key, label;
  final int lines;
  final bool numeric, integer, nullable, labelAbove;
  final Map<String, String>? options;
  const FieldSpec(
    this.key,
    this.label, {
    this.lines = 1,
    this.numeric = false,
    this.integer = false,
    this.nullable = false,
    this.labelAbove = false,
    this.options,
  });
}

Future<bool> editFields(
  BuildContext context, {
  required String title,
  required Json initial,
  required List<FieldSpec> fields,
  required Future<void> Function(Json) save,
  void Function(Json)? draft,
  String submitLabel = 'Сохранить',
  String progressLabel = 'Сохраняю…',
}) async {
  final controllers = {
    for (final field in fields)
      field.key: TextEditingController(
        text: initial[field.key]?.toString() ?? '',
      ),
  };
  final values = Map<String, dynamic>.from(initial);
  for (final field in fields) {
    if (field.options?.isNotEmpty == true &&
        !field.options!.containsKey(values[field.key])) {
      values[field.key] = field.options!.keys.first;
    }
  }
  String? error;
  bool saving = false;
  Json collect() {
    for (final field in fields) {
      if (field.options != null) continue;
      final text = controllers[field.key]!.text;
      if (field.numeric || field.integer) {
        if (text.isEmpty) {
          values[field.key] = null;
        } else {
          final number = num.tryParse(text.replaceAll(',', '.'));
          if (number == null || field.integer && number != number.round()) {
            throw ArgumentError(
              '${field.label}: укажи ${field.integer ? 'целое число' : 'число'}.',
            );
          }
          values[field.key] = field.integer ? number.toInt() : number;
        }
      } else {
        values[field.key] = field.nullable && text.isEmpty ? null : text;
      }
    }
    return Map<String, dynamic>.from(values);
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _FormControllerOwner(
      controllers: controllers,
      child: StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (field.labelAbove)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(field.label),
                            ),
                          field.options == null
                              ? TextField(
                                  controller: controllers[field.key],
                                  maxLines: field.lines,
                                  minLines: field.lines > 1 ? 2 : 1,
                                  keyboardType: field.numeric || field.integer
                                      ? const TextInputType.numberWithOptions(
                                          decimal: true,
                                          signed: true,
                                        )
                                      : TextInputType.multiline,
                                  decoration: InputDecoration(
                                    labelText: field.labelAbove
                                        ? null
                                        : field.label,
                                    alignLabelWithHint: true,
                                  ),
                                  onChanged: (_) {
                                    try {
                                      draft?.call(collect());
                                    } catch (_) {
                                      draft?.call({
                                        ...values,
                                        ...controllers.map(
                                          (k, c) => MapEntry(k, c.text),
                                        ),
                                      });
                                    }
                                  },
                                )
                              : DropdownButtonFormField<String>(
                                  initialValue:
                                      field.options!.containsKey(
                                        values[field.key]?.toString(),
                                      )
                                      ? values[field.key]?.toString()
                                      : field.options!.keys.firstOrNull,
                                  hint: const Text('No Data'),
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: field.labelAbove
                                        ? null
                                        : field.label,
                                  ),
                                  items: field.options!.entries
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e.key,
                                          child: Text(e.value),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() => values[field.key] = value);
                                    try {
                                      draft?.call(collect());
                                    } catch (_) {}
                                  },
                                ),
                        ],
                      ),
                    ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context, false),
              child: const Text('Закрыть'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() => saving = true);
                      try {
                        await save(collect());
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        setState(() {
                          error = e.toString();
                          saving = false;
                        });
                      }
                    },
              child: Text(saving ? progressLabel : submitLabel),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

/// Dialog pop completes before its reverse animation unmounts the fields.
/// Keep their controllers alive until the route's widget is actually disposed.
class _FormControllerOwner extends StatefulWidget {
  final Map<String, TextEditingController> controllers;
  final Widget child;
  const _FormControllerOwner({required this.controllers, required this.child});
  @override
  State<_FormControllerOwner> createState() => _FormControllerOwnerState();
}

class _FormControllerOwnerState extends State<_FormControllerOwner> {
  @override
  Widget build(BuildContext context) => widget.child;
  @override
  void dispose() {
    for (final controller in widget.controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}

Widget metricCard(
  String title,
  dynamic current,
  dynamic target,
  dynamic percent, {
  String unit = '',
  VoidCallback? onTap,
}) => Card(
  child: InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(color: Color(0xff6b7280), fontSize: 13),
          ),
          const SizedBox(height: 12),
          Text(
            current == null
                ? 'No Data'
                : '$current${unit.isEmpty ? '' : ' $unit'}',
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            target == null ? 'Цель · No Data' : 'Ориентир · $target $unit',
            style: const TextStyle(fontSize: 12, color: Color(0xff6b7280)),
          ),
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: percent == null
                ? 0
                : ((percent as num) / 100).clamp(0.0, 1.0),
            minHeight: 5,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: const Color(0xffe8eae9),
          ),
          const SizedBox(height: 7),
          Text(
            percent == null ? 'No Data' : '$percent%',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  ),
);
Widget sectionTitle(String title, {Widget? trailing}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 18),
  child: LayoutBuilder(
    builder: (context, constraints) {
      final heading = Text(
        title,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -.4,
        ),
      );
      if (constraints.maxWidth < 650 && trailing != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [heading, const SizedBox(height: 8), trailing],
        );
      }
      return Row(
        children: [
          Expanded(child: heading),
          ?trailing,
        ],
      );
    },
  ),
);
