import 'package:flutter/material.dart';

import 'repository.dart';

/// The same recovery control in the full and compact timer.
class TimerCommandNotice extends StatelessWidget {
  final DashboardRepository repo;
  final VoidCallback retry;
  const TimerCommandNotice({
    super.key,
    required this.repo,
    required this.retry,
  });

  @override
  Widget build(BuildContext context) {
    if (!repo.timerPending && !repo.timerBusy) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            repo.durableTimer
                ? 'Сохранено на устройстве · ${repo.pending.where((q) => q['route'] == '/api/timer').length} действий ждут синхронизации'
                : repo.timerBusy
                ? 'Подтверждаю действие…'
                : 'Ответ сервера не получен. Действие сохранено и будет проверено при связи.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (!repo.timerBusy)
            TextButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.sync, color: Colors.white),
              label: Text(
                repo.durableTimer ? 'Синхронизировать' : 'Проверить действие',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
