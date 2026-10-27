import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'domain.dart';
import 'model_link.dart';
import 'repository.dart';

/// Links are a presentation of the raw note, never a rewrite of its contents.
List<Uri> notesLinks(String text) {
  final found = <String, Uri>{};
  for (final match in RegExp(
    r'''https?://[^\s<>"\x00-\x1f]+''',
  ).allMatches(text)) {
    var raw = match.group(0)!;
    raw = raw.replaceFirst(RegExp(r'[.,;!]+$'), '');
    while (raw.endsWith(')') &&
        ')'.allMatches(raw).length > '('.allMatches(raw).length) {
      raw = raw.substring(0, raw.length - 1);
    }
    final uri = modelLinkUri(raw);
    if (uri != null) found.putIfAbsent(uri.toString(), () => uri);
  }
  return found.values.toList();
}

class GoalNotesCell extends StatelessWidget {
  final DashboardRepository repo;
  final Json goal, column;
  const GoalNotesCell({
    super.key,
    required this.repo,
    required this.goal,
    required this.column,
  });

  @override
  Widget build(BuildContext context) {
    final raw = object(goal['customValues'])[column['id']]?.toString() ?? '';
    return TextButton(
      key: ValueKey('goal-notes:${goal['id']}:${column['id']}'),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => GoalNotesEditor(repo: repo, goal: goal, column: column),
      ),
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        minimumSize: const Size(32, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        children: [
          const Icon(Icons.notes_outlined, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              raw.isEmpty ? 'Написать заметку' : raw,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Tooltip(
            message: 'Открыть заметку целиком',
            child: Icon(Icons.open_in_full, size: 14),
          ),
        ],
      ),
    );
  }
}

class GoalNotesEditor extends StatefulWidget {
  final DashboardRepository repo;
  final Json goal, column;
  const GoalNotesEditor({
    super.key,
    required this.repo,
    required this.goal,
    required this.column,
  });
  @override
  State<GoalNotesEditor> createState() => _GoalNotesEditorState();
}

class _GoalNotesEditorState extends State<GoalNotesEditor> {
  late final String draftKey;
  late final TextEditingController controller;
  dynamic before;
  String? error;
  bool saving = false;
  int get limit => (widget.column['maxLength'] as int?) ?? 30000;

  @override
  void initState() {
    super.initState();
    draftKey =
        'goalNote:${widget.repo.serverId}:${widget.goal['id']}:${widget.column['id']}';
    final draft = object(widget.repo.local.get(draftKey));
    final current = object(widget.goal['customValues'])[widget.column['id']];
    before = draft.containsKey('before') ? draft['before'] : current;
    controller = TextEditingController(
      text: (draft['text'] ?? current ?? '').toString(),
    );
  }

  void retain(String text) =>
      widget.repo.local.set(draftKey, {'text': text, 'before': before});

  void save() {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final text = controller.text;
      retain(text);
      if (text.length > limit) {
        throw FormatException(
          'Заметка: не больше $limit символов. Черновик сохранён.',
        );
      }
      widget.repo.editGoalCell(
        widget.goal['id'].toString(),
        widget.column['id'].toString(),
        before,
        text,
      );
      widget.repo.local.remove(draftKey);
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        error = e is StateError
            ? e.message.toString()
            : e is FormatException
            ? e.message
            : e.toString();
        saving = false;
      });
    }
  }

  Future<void> openLink(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть ссылку.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 840, maxHeight: 780),
      child: SizedBox(
        width: double.infinity,
        height: min(780.0, MediaQuery.sizeOf(context).height * .86),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.column['title'].toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть заметку',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                widget.goal['title'].toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('goal-note-editor'),
                  controller: controller,
                  autofocus: true,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  readOnly: saving,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: 'Подробности, абзацы и ссылки…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: retain,
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final links = notesLinks(value.text);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (links.isNotEmpty)
                        ExpansionTile(
                          key: const ValueKey('goal-note-links'),
                          title: Text('Ссылки · ${links.length}'),
                          tilePadding: EdgeInsets.zero,
                          dense: true,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 112),
                              child: ListView(
                                shrinkWrap: true,
                                children: [
                                  for (final uri in links)
                                    TextButton.icon(
                                      onPressed: () => openLink(uri),
                                      icon: const Icon(
                                        Icons.open_in_new,
                                        size: 16,
                                      ),
                                      label: Text(
                                        uri.toString(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            error!,
                            key: const ValueKey('goal-note-error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.end,
                        children: [
                          Text(
                            '${value.text.length} / $limit',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Закрыть'),
                          ),
                          FilledButton(
                            onPressed: saving ? null : save,
                            child: const Text('Сохранить'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
