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
            repo.timerBusy ? 'Подтверждаю действие…' : 'Ответ сервера не получен. Действие сохранено и будет проверено при связи.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (!repo.timerBusy)
            TextButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.sync, color: Colors.white),
              label: const Text(
                'Проверить действие',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
