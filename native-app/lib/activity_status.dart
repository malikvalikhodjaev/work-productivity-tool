import 'package:flutter/material.dart';

import 'repository.dart';

String syncTime(Object? raw) {
  final at = DateTime.tryParse(raw?.toString() ?? '')
      ?.toUtc()
      .add(const Duration(hours: 5));
  return at == null
      ? ''
      : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

class ActivityStatus extends StatelessWidget {
  final DashboardRepository repo;
  final bool showTimer;
  final VoidCallback? inspect;
  const ActivityStatus({
    super.key,
    required this.repo,
    this.showTimer = true,
    this.inspect,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final pending = repo.pending;
      final conflicts = pending.where((q) => q['state'] == 'conflict').length;
      final last = syncTime(repo.local.get('lastSyncAt'));
      final error = repo.local.get('lastSyncError');
      final label = conflicts > 0
          ? 'Нужен разбор · $conflicts изменений сохранены на устройстве'
          : repo.syncing
          ? 'Синхронизация…${pending.isEmpty ? '' : ' · изменений: ${pending.length}'}'
          : pending.isNotEmpty
          ? 'Сохранено на устройстве · ожидает отправки: ${pending.length}${error == null ? '' : ' · нет связи'}'
          : error != null
          ? 'Нет связи · локальные данные доступны${last.isEmpty ? '' : ' · последняя синхронизация $last'}'
          : last.isNotEmpty
          ? 'Синхронизировано · $last'
          : 'Локальное хранилище готово · первая синхронизация ещё не выполнена';
      final active = repo.active;
      final timer = active == null
          ? null
          : '${repo.timerBusy
                ? 'Сохраняю действие'
                : active['status'] == 'paused'
                ? 'На паузе'
                : active['phase'] == 'work'
                ? 'Таймер запущен'
                : 'Перерыв'} · ${active['title'] ?? 'Без названия'}';
      return Semantics(
        liveRegion: true,
        child: Container(
          key: const ValueKey('activity-status'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      conflicts > 0
                          ? Icons.warning_amber
                          : repo.syncing
                          ? Icons.sync
                          : error != null
                          ? Icons.cloud_off_outlined
                          : pending.isNotEmpty
                          ? Icons.save_outlined
                          : Icons.cloud_done_outlined,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, softWrap: true)),
                  IconButton(
                    tooltip: conflicts > 0
                        ? 'Синхронизировать; конфликты доступны в Данных'
                        : 'Синхронизировать сейчас',
                    onPressed: repo.syncing ? null : repo.synchronize,
                    icon: const Icon(Icons.sync),
                  ),
                ],
              ),
              if (showTimer && timer != null)
                Text(
                  timer,
                  key: const ValueKey('active-timer-state'),
                  softWrap: true,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              if ((conflicts > 0 || error != null) && inspect != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: inspect,
                    icon: const Icon(Icons.manage_search),
                    label: const Text('Открыть данные и разбор'),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
