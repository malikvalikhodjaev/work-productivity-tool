import 'package:flutter/material.dart';

import 'repository.dart';

class SyncPanel extends StatelessWidget {
  final DashboardRepository repo;
  const SyncPanel({super.key, required this.repo});

  String stamp(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')
        ?.toUtc()
        .add(const Duration(hours: 5));
    if (date == null) return 'Ещё не выполнялась';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = repo.pending
        .where((p) => p['state'] == 'conflict')
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Синхронизация',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Изменения сначала сохраняются в базе на устройстве. Для записи и управления таймером не нужно ждать ответа сервера.',
            ),
            const SizedBox(height: 12),
            Text(
              'Ожидает отправки: ${repo.pending.length} · Требует разбора: $conflicts',
            ),
            Text(
              'Последняя связь с сервером: ${stamp(repo.local.get('lastSyncAt'))}',
            ),
            Text('Локальные черновики: ${repo.local.drafts.length}'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Автоматическая синхронизация'),
              subtitle: const Text(
                'При доступном сервере: после сохранения и каждые 30 секунд, пока приложение работает.',
              ),
              value: repo.automaticSync,
              onChanged: repo.setAutomaticSync,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: repo.syncing ? null : repo.synchronize,
                icon: const Icon(Icons.sync),
                label: Text(
                  repo.syncing ? 'Синхронизация…' : 'Синхронизировать',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(repo.status),
            if (repo.local.get('lastSyncError') != null)
              ExpansionTile(
                title: const Text('Подробности синхронизации'),
                children: [
                  SelectableText(repo.local.get('lastSyncError').toString()),
                ],
              ),
            if (conflicts > 0)
              const Text(
                'Исходники сохранены. Открой записи ниже и разбери конфликт перед учётом на сервере.',
              ),
          ],
        ),
      ),
    );
  }
}
