import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain.dart';
import 'repository.dart';

class InboxWidget extends StatefulWidget {
  final DashboardRepository repo;
  final ValueChanged<String> openWriting;
  const InboxWidget({super.key, required this.repo, required this.openWriting});
  @override
  State<InboxWidget> createState() => _InboxWidgetState();
}

class _InboxWidgetState extends State<InboxWidget> {
  String filter = 'new';
  @override
  Widget build(BuildContext context) {
    final inbox = widget.repo.cache('inbox'),
        entries = rows(inbox['entries'])
            .map((e) => widget.repo.entity('inbox:${e['id']}', e))
            .toList();
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.inbox_outlined),
        title: Text(
          'Входящие мысли · ${entries.where((e) => e['status'] == 'new').length}',
        ),
        subtitle: const Text('Текст и голосовые из твоего Telegram-бота'),
        childrenPadding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final choice in const {
                'new': 'Не разобрано',
                'reviewed': 'Разобрано',
                'archived': 'Архив',
                'favorites': 'Избранное',
              }.entries)
                ChoiceChip(
                  label: Text(choice.value),
                  selected: filter == choice.key,
                  onSelected: (_) => setState(() => filter = choice.key),
                ),
            ],
          ),
          if (entries
              .where(
                (e) => filter == 'favorites'
                    ? e['favorite'] == true
                    : e['status'] == filter,
              )
              .isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No Data · сообщения боту появятся здесь.'),
            ),
          for (final item in entries.where(
            (e) => filter == 'favorites'
                ? e['favorite'] == true
                : e['status'] == filter,
          ))
            ListTile(
              leading: Icon(
                item['favorite'] == true
                    ? Icons.star
                    : item['kind'] == 'voice'
                    ? Icons.mic_none
                    : Icons.notes,
              ),
              title: Text(
                item['title'].toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item['writingId'] != null
                    ? 'Есть черновик ↗'
                    : (item['sourceText'] ?? '').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing:
                  widget.repo.pending.any(
                    (q) => q['entity'] == 'inbox:${item['id']}',
                  )
                  ? const Icon(Icons.cloud_upload_outlined, size: 18)
                  : null,
              onTap: () =>
                  showDialog<String>(
                    context: context,
                    builder: (_) => _InboxReview(repo: widget.repo, item: item),
                  ).then((id) {
                    if (id != null) widget.openWriting(id);
                  }),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Подключение бота — в веб-дашборде: Письмо → Входящие мысли → Telegram.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxReview extends StatefulWidget {
  final DashboardRepository repo;
  final Json item;
  const _InboxReview({required this.repo, required this.item});
  @override
  State<_InboxReview> createState() => _InboxReviewState();
}

class _InboxReviewState extends State<_InboxReview> {
  late final Json source;
  late final TextEditingController title, body, transcript, notes;
  AudioPlayer? player;
  StreamSubscription<PlayerState>? subscription;
  bool playing = false;
  bool loadingAudio = false;
  Uint8List? voiceBytes;
  bool favorite = false;
  String? error;
  String get entity => 'inbox:${widget.item['id']}';
  @override
  void initState() {
    super.initState();
    source = widget.repo.local.draft(entity) ?? widget.item;
    title = TextEditingController(text: source['title'] ?? '');
    body = TextEditingController(
      text: source['body'] ?? source['sourceText'] ?? '',
    );
    favorite = source['favorite'] == true;
    transcript = TextEditingController(text: source['transcript'] ?? '');
    notes = TextEditingController(text: source['notes'] ?? '');
  }

  Json fields() => {
    'id': source['id'],
    'title': title.text,
    'body': body.text,
    'favorite': favorite,
    'transcript': transcript.text,
    'notes': notes.text,
  };
  void keep() => widget.repo.local.keepDraft(entity, {...source, ...fields()});
  void save(String action) {
    try {
      keep();
      if (title.text.length > 300 ||
          body.text.length > 80000 ||
          transcript.text.length > 80000 ||
          notes.text.length > 80000) {
        throw ArgumentError('Тема — до 300 знаков, текст — до 80 000.');
      }
      widget.repo.nativeSave(
        'inbox',
        action,
        fields(),
        entity,
        draft: {
          ...source,
          ...fields(),
          'status': action == 'archive'
              ? 'archived'
              : action == 'reopen'
              ? 'new'
              : action == 'convert'
              ? 'reviewed'
              : source['status'],
        },
        expectedUpdatedAt: source['updatedAt'],
      );
      Navigator.pop(context);
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> toggleAudio(Json audio) async {
    if (loadingAudio) return;
    setState(() {
      error = null;
      loadingAudio = true;
    });
    try {
      final compatible = Theme.of(context).platform == TargetPlatform.windows;
      if (player?.state == PlayerState.playing) {
        await player!.pause();
      } else if (player?.state == PlayerState.paused) {
        await player!.resume();
      } else {
        voiceBytes ??= Uint8List.fromList(
          await widget.repo.inboxAudio(
            audio['url'].toString(),
            compatible: compatible,
          ),
        );
        if (!mounted) return;
        if (player == null) {
          player = AudioPlayer();
          subscription = player!.onPlayerStateChanged.listen(
            (state) {
              if (mounted) {
                setState(() => playing = state == PlayerState.playing);
              }
            },
            onError: (Object _) {
              if (mounted) {
                setState(() {
                  playing = false;
                  error =
                      'Запись загружена, но плеер не смог её воспроизвести.';
                });
              }
            },
          );
          await player!.setReleaseMode(ReleaseMode.stop);
        }
        if (!mounted) return;
        await player!.play(
          BytesSource(
            voiceBytes!,
            mimeType: compatible ? 'audio/wav' : audio['mime'] as String?,
          ),
        );
      }
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } on PlatformException {
      if (mounted) {
        setState(
          () => error = 'Запись загружена, но плеер не поддержал её формат. Попробуй открыть запись повторно.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Не удалось загрузить голосовую. Проверь подключение к серверу и повтори.',
        );
      }
    } finally {
      if (mounted) setState(() => loadingAudio = false);
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    if (player != null) unawaited(player!.dispose());
    title.dispose();
    body.dispose();
    transcript.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queued = widget.repo.pending.any(
          (q) => q['entity'] == entity && q['attempted'] == 1,
        ),
        audio = object(widget.item['audio']);
    return AlertDialog(
      title: const Text('Разобрать мысль'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                readOnly: queued,
                onChanged: (_) => keep(),
                decoration: const InputDecoration(labelText: 'Тема мысли'),
                maxLength: 300,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: body,
                readOnly: queued,
                onChanged: (_) => keep(),
                minLines: 4,
                maxLines: 12,
                decoration: const InputDecoration(labelText: 'Заметка'),
              ),
              if ((source['sourceText'] ?? '').toString().isNotEmpty)
                ExpansionTile(
                  title: const Text('Исходное сообщение'),
                  children: [SelectableText(source['sourceText'].toString())],
                ),
              if (audio.isNotEmpty)
                TextButton.icon(
                  onPressed: audio['status'] == 'ready' && !loadingAudio
                      ? () => toggleAudio(audio)
                      : null,
                  icon: loadingAudio
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(playing ? Icons.pause : Icons.play_arrow),
                  label: Text(
                    loadingAudio
                        ? 'Загрузка…'
                        : playing
                        ? 'Пауза'
                        : audio['status'] == 'ready'
                        ? 'Прослушать голосовую'
                        : 'Аудио загружается',
                  ),
                ),
              if (audio.isNotEmpty && !widget.repo.online)
                const Text(
                  'Прослушивание доступно при связи с сервером.',
                  style: TextStyle(fontSize: 12),
                ),
              if (source['kind'] == 'voice')
                TextField(
                  controller: transcript,
                  readOnly: queued,
                  onChanged: (_) => keep(),
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Расшифровка / суть голосовой',
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                readOnly: queued,
                onChanged: (_) => keep(),
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Мои мысли при разборе',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Что здесь ценно? Что стоит уточнить или сделать дальше?',
                style: TextStyle(fontSize: 12),
              ),
              if (queued)
                const Text(
                  'Разбор сохранён на устройстве и ожидает синхронизации.',
                ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
        TextButton.icon(
          onPressed: queued
              ? null
              : () {
                  setState(() => favorite = !favorite);
                  save('save');
                },
          icon: Icon(favorite ? Icons.star : Icons.star_outline),
          label: Text(favorite ? 'В избранном' : 'В избранное'),
        ),
        TextButton(
          onPressed: queued
              ? null
              : () =>
                    save(source['status'] == 'archived' ? 'reopen' : 'archive'),
          child: Text(
            source['status'] == 'archived' ? 'Вернуть' : 'Обработал · в архив',
          ),
        ),
        TextButton(
          onPressed: queued ? null : () => save('save'),
          child: const Text('Сохранить разбор'),
        ),
        FilledButton(
          onPressed: queued
              ? null
              : source['writingId'] != null
              ? () => Navigator.pop(context, source['writingId'].toString())
              : () => save('convert'),
          child: Text(
            source['writingId'] != null
                ? 'Открыть черновик'
                : 'Создать черновик',
          ),
        ),
      ],
    );
  }
}
