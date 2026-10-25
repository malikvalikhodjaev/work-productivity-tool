import 'package:flutter/material.dart';

import 'domain.dart';
import 'time_composition.dart';
import 'repository.dart';

/// Same repository/session on every dashboard tab; never owns another timer.
class DashboardTimerBar extends StatelessWidget {
  final DashboardRepository repo;
  final Listenable pulse;
  final VoidCallback open, pause, finish;
  const DashboardTimerBar({
    super.key,
    required this.repo,
    required this.pulse,
    required this.open,
    required this.pause,
    required this.finish,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: pulse,
    builder: (context, _) {
      final s = repo.active;
      if (s == null) return const SizedBox.shrink();
      final paused = s['status'] == 'paused' && !inLeisure(s);
      return Material(
        key: const ValueKey('dashboard-timer-bar'),
        color: const Color(0xff243b30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 14),
            child: LayoutBuilder(
              builder: (context, box) {
                final clock = TextButton(
                  onPressed: open,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: Text(
                    clockOf(s, repo.now),
                    key: const ValueKey('dashboard-timer-clock'),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                );
                final description = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paused
                          ? 'На паузе · ${pauseClock(s, repo.now)}'
                          : inLeisure(s) || s['phase'] != 'work'
                          ? 'Перерыв'
                          : 'Идёт работа',
                      style: TextStyle(
                        color: paused
                            ? const Color(0xffffdc9a)
                            : Colors.white70,
                      ),
                    ),
                    Text(caption(s), softWrap: true),
                  ],
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton(
                      onPressed: repo.timerBusy || pomodoroExpired(s, repo.now)
                          ? null
                          : pause,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: Text(paused ? 'Продолжить' : 'Пауза'),
                    ),
                    FilledButton.tonal(
                      onPressed: repo.timerBusy ? null : finish,
                      child: const Text('Учесть'),
                    ),
                    IconButton(
                      onPressed: open,
                      tooltip: 'Открыть крупный таймер',
                      icon: const Icon(Icons.open_in_full, color: Colors.white),
                    ),
                  ],
                );
                if (box.maxWidth < 700) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          clock,
                          const SizedBox(width: 12),
                          Expanded(child: description),
                        ],
                      ),
                      actions,
                    ],
                  );
                }
                return Row(
                  children: [
                    clock,
                    const SizedBox(width: 16),
                    Expanded(child: description),
                    const SizedBox(width: 12),
                    actions,
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
