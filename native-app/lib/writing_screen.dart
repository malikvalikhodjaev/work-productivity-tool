import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;

import 'domain.dart';
import 'section_analytics.dart';
import 'repository.dart';
import 'reflection_hints.dart';
import 'inbox_widget.dart';

Json editorDocument(Json source, {bool toServer = false}) => {
  'ops': rows(source['ops']).map((op) {
    final insert = op['insert'];
    return {
      ...op,
      if (insert is Map && insert.containsKey('divider'))
        'insert': {'divider': toServer ? true : 'true'},
    };
  }).toList(),
};

class DividerBuilder extends q.EmbedBuilder {
  const DividerBuilder();
  @override
  String get key => 'divider';
  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) =>
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Divider(),
      );
}

class WritingScreen extends StatefulWidget {
  final DashboardRepository repo;
  const WritingScreen({super.key, required this.repo});
  @override
  State<WritingScreen> createState() => _WritingScreenState();
}

class _WritingScreenState extends State<WritingScreen> {
  String? selected, month;
  String mode = 'draft';
  final title = TextEditingController();
  final date = TextEditingController(text: today());
  final editorFocus = FocusNode(debugLabel: 'Essay editor');
  final editorScroll = ScrollController();
  q.QuillController controller = q.QuillController.basic();
  Timer? debounce;
  StreamSubscription<q.DocChange>? changesSubscription;
  bool converting = false;
  String status = '';
  bool showTrash = false;
  bool showFavorites = false;
  DashboardRepository get repo => widget.repo;
  bool get favorite => repo.writingEntries.any(
    (entry) => entry['id'] == selected && entry['favorite'] == true,
  );
  bool get inTrash =>
      selected != null &&
      repo.writingEntries.any(
        (entry) => entry['id'] == selected && entry['trashedAt'] != null,
      );
  void open(Json article) {
    debounce?.cancel();
    if (selected != null) persistDraft();
    controller.removeListener(changed);
    changesSubscription?.cancel();
    controller.dispose();
    final saved =
        repo.local.draft('composer:${article['id']}') ??
        repo.local.draft('writing:${article['id']}') ??
        repo.cache('writing:${article['id']}');
    final entry = saved.isNotEmpty ? saved : article;
    selected = article['id'].toString();
    title.text = (entry['title'] ?? '').toString();
    date.text = (entry['date'] ?? today()).toString();
    mode = (entry['status'] ?? 'draft').toString();
    final doc = object(entry['document']).isNotEmpty
        ? object(entry['document'])
        : {
            'ops': [
              {'insert': '\n'},
            ],
          };
    controller = q.QuillController(
      document: q.Document.fromJson(editorDocument(doc)['ops']),
      selection: const TextSelection.collapsed(offset: 0),
    );
    controller.addListener(changed);
    changesSubscription = controller.changes.listen((event) {
      final typed = event.change.operations.any(
        (op) => op.isInsert && (op.data == '-' || op.data == '\n'),
      );
      if (!typed) return;
      final current = controller;
      scheduleMicrotask(() {
        if (!mounted || current != controller || converting) return;
        final text = controller.document.toPlainText();
        final offset = controller.selection.baseOffset;
        if (offset < 1 || offset > text.length) return;
        final end = text[offset - 1] == '\n' ? offset - 1 : offset;
        if (end < 3) return;
        final start = text.lastIndexOf('\n', end - 1) + 1;
        if (text.substring(start, end) != '---' ||
            controller.getSelectionStyle().attributes.containsKey('list')) {
          return;
        }
        converting = true;
        controller.document.history.lastRecorded = 0;
        controller.replaceText(
          start,
          3,
          const q.BlockEmbed('divider', 'true'),
          TextSelection.collapsed(offset: start + 1),
        );
        controller.document.history.lastRecorded = 0;
        converting = false;
        changed();
      });
    });
    setState(() => status = '');
  }

  Json article() => {
    'id': selected,
    'title': title.text,
    'date': date.text,
    'status': mode,
    'favorite': favorite,
    'document': editorDocument({
      'ops': controller.document.toDelta().toJson(),
    }, toServer: true),
  };
  void persistDraft() {
    if (selected != null && !inTrash) {
      repo.local.keepDraft('composer:$selected', article());
    }
  }

  void changed() {
    if (converting) return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), persistDraft);
  }

  @override
  void dispose() {
    debounce?.cancel();
    persistDraft();
    controller.removeListener(changed);
    changesSubscription?.cancel();
    controller.dispose();
    title.dispose();
    date.dispose();
    editorFocus.dispose();
    editorScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = repo.writingEntries
        .where((a) => (a['trashedAt'] != null) == showTrash)
        .where((a) => !showFavorites || a['favorite'] == true)
        .toList();
    final trashed = inTrash;
    controller.readOnly = trashed;
    final pendingWriting = repo.pending.any(
      (p) => p['entity'] == 'writing:$selected',
    );
    source.sort(
      (a, b) =>
          (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()),
    );
    final archive = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () {
            showTrash = false;
            showFavorites = false;
            open({'id': uuid.v4(), 'date': today(), 'status': 'draft'});
          },
          icon: const Icon(Icons.add),
          label: const Text('Новая запись'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Публикации по месяцам',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        TextButton(
          onPressed: () => setState(() {
            month = null;
            showTrash = false;
            showFavorites = false;
          }),
          child: const Text('Все записи'),
        ),
        TextButton.icon(
          onPressed: () => setState(() {
            showTrash = false;
            showFavorites = true;
            month = null;
          }),
          icon: const Icon(Icons.star_outline),
          label: Text(
            'Избранное · ${repo.writingEntries.where((a) => a['favorite'] == true && a['trashedAt'] == null).length}',
          ),
        ),
        TextButton.icon(
          onPressed: () => setState(() {
            month = null;
            showTrash = true;
            showFavorites = false;
          }),
          icon: const Icon(Icons.delete_outline),
          label: Text(
            'Корзина · ${repo.writingEntries.where((a) => a['trashedAt'] != null).length}',
          ),
        ),
        ...rows(repo.cache('writing')['months']).map(
          (m) => TextButton(
            onPressed: () => setState(() {
              month = m['month'].toString();
              showTrash = false;
              showFavorites = false;
            }),
            child: Text('${m['month']} · ${m['count']}'),
          ),
        ),
        ...source
            .where(
              (a) => month == null || a['date'].toString().startsWith(month!),
            )
            .map(
              (a) => ListTile(
                leading: a['favorite'] == true
                    ? const Icon(Icons.star, size: 18)
                    : null,
                selected: selected == a['id'],
                title: Text(
                  (a['title'] ?? '').toString().isEmpty
                      ? 'Без темы'
                      : a['title'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${a['date']} · ${a['status'] == 'published' ? 'Опубликовано' : 'Черновик'}',
                ),
                onTap: () => open(a),
              ),
            ),
      ],
    );
    final editor = selected == null
        ? const Center(child: Text('Выбери запись или начни новое эссе.'))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: title,
                readOnly: trashed,
                onChanged: (_) => persistDraft(),
                decoration: const InputDecoration(labelText: 'Тема записи'),
                maxLength: 300,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: date,
                      readOnly: trashed,
                      onChanged: (_) => persistDraft(),
                      decoration: const InputDecoration(
                        labelText: 'Дата · YYYY-MM-DD',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: mode,
                    items: const [
                      DropdownMenuItem(value: 'draft', child: Text('Черновик')),
                      DropdownMenuItem(
                        value: 'published',
                        child: Text('Публикация'),
                      ),
                    ],
                    onChanged: trashed
                        ? null
                        : (value) {
                            setState(() => mode = value!);
                            persistDraft();
                          },
                  ),
                ],
              ),
              if (!trashed)
                Wrap(
                  children: [
                    for (var level = 1; level <= 4; level++)
                      TextButton(
                        onPressed: () => controller.formatSelection(
                          q.Attribute.fromKeyValue('header', level),
                        ),
                        child: Text('H$level'),
                      ),
                    TextButton(
                      onPressed: () => controller.formatSelection(
                        q.Attribute.fromKeyValue('header', null),
                      ),
                      child: const Text('Текст'),
                    ),
                  ],
                ),
              if (!trashed)
                q.QuillSimpleToolbar(
                  controller: controller,
                  config: const q.QuillSimpleToolbarConfig(
                    showFontFamily: false,
                    showFontSize: false,
                    showColorButton: false,
                    showBackgroundColorButton: false,
                    showHeaderStyle: false,
                    showCodeBlock: false,
                    showListCheck: false,
                    showSubscript: false,
                    showSuperscript: false,
                    showSearchButton: false,
                  ),
                ),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(minHeight: 320),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xffe6e8ec)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: q.QuillEditor.basic(
                  controller: controller,
                  focusNode: editorFocus,
                  scrollController: editorScroll,
                  config: const q.QuillEditorConfig(
                    placeholder: 'Пиши свободно. Что сейчас требует внимания?',
                    embedBuilders: [DividerBuilder()],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: trashed
                        ? null
                        : () {
                            try {
                              persistDraft();
                              repo.saveWriting(article());
                              setState(
                                () => status =
                                    'Сохранено локально · отправка в очереди',
                              );
                            } catch (e) {
                              setState(() => status = e.toString());
                            }
                          },
                    child: const Text('Сохранить'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        trashed ||
                            repo.pending.any(
                              (p) =>
                                  p['entity'] == 'writing:$selected' &&
                                  (p['attempted'] == 1 ||
                                      object(p['body'])['action'] != 'save'),
                            )
                        ? null
                        : () {
                            try {
                              persistDraft();
                              repo.saveWriting({
                                ...article(),
                                'favorite': !favorite,
                              });
                              setState(
                                () => status =
                                    'Метка избранного сохранена на устройстве',
                              );
                            } catch (e) {
                              setState(() => status = e.toString());
                            }
                          },
                    icon: Icon(favorite ? Icons.star : Icons.star_outline),
                    label: Text(favorite ? 'В избранном' : 'В избранное'),
                  ),
                  OutlinedButton.icon(
                    onPressed: pendingWriting
                        ? null
                        : () {
                            try {
                              if (trashed) {
                                repo.restoreWriting(selected!);
                              } else {
                                persistDraft();
                                repo.saveWriting(article(), trash: true);
                              }
                              editorFocus.unfocus();
                              setState(
                                () => status = trashed
                                    ? 'Восстановление сохранено локально · отправка в очереди'
                                    : 'В корзине · запись можно восстановить',
                              );
                            } catch (e) {
                              setState(() => status = e.toString());
                            }
                          },
                    icon: Icon(trashed ? Icons.restore : Icons.delete_outline),
                    label: Text(trashed ? 'Восстановить' : 'Удалить запись'),
                  ),
                ],
              ),
              if (status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(status),
                ),
              const SizedBox(height: 18),
              ReflectionHints(repo: repo),
            ],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InboxWidget(
          repo: repo,
          openWriting: (id) => open(repo.cache('writing:$id')),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, size) => size.maxWidth > 850
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 230, child: archive),
                    const SizedBox(width: 28),
                    Expanded(child: editor),
                  ],
                )
              : Column(
                  children: [
                    ExpansionTile(
                      title: const Text('Архив записей'),
                      children: [archive],
                    ),
                    editor,
                  ],
                ),
        ),
        WritingAnalytics(repo: repo),
      ],
    );
  }
}
