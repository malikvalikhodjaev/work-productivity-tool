import 'package:flutter/material.dart';

import 'domain.dart';
import 'leisure.dart';

const focusColors = {
  'green': Color(0xff243b30),
  'evening': Color(0xff40394f),
  'desert': Color(0xff826246),
  'lofi': Color(0xff343e57),
};

class CompactTimer extends StatelessWidget {
  final Json? session;
  final int now;
  final String theme;
  final VoidCallback pause;
  final VoidCallback finish;
  final Widget checklist;
  final bool busy;
  final Widget? commandStatus;
  final Widget? dailyProblem;

  const CompactTimer({
    super.key,
    required this.session,
    required this.now,
    required this.theme,
    required this.pause,
    required this.finish,
    required this.checklist,
    this.busy = false,
    this.commandStatus,
    this.dailyProblem,
  });

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: focusColors[theme] ?? focusColors['green'],
        borderRadius: BorderRadius.circular(20),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?dailyProblem,
            Text(
              s == null
                  ? 'Сеанс завершён'
                  : inLeisure(s)
                  ? 'Leisure · до ${leisureTime(s)}'
                  : s['status'] == 'paused'
                  ? 'Пауза'
                  : s['mode'] == 'pomodoro'
                  ? 'Pomodoro'
                  : 'Stopwatch',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                s == null ? '—' : clockOf(s, now),
                style: const TextStyle(
                  fontSize: 76,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s == null
                  ? 'Открой дашборд, чтобы выбрать следующую работу'
                  : caption(s),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, height: 1.35),
            ),
            if (s != null) ...[
              if (inLeisure(s)) LeisureInfo(session: s, now: now),
              const SizedBox(height: 8),
              Text(
                '${(elapsedMs(s, now) / 60000).toStringAsFixed(1)} мин',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              ?commandStatus,
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: busy ? null : pause,
                    child: Text(
                      inLeisure(s)
                          ? 'Вернуться к работе'
                          : s['status'] == 'paused'
                          ? 'Продолжить'
                          : 'Пауза',
                    ),
                  ),
                  FilledButton(
                    onPressed: busy ? null : finish,
                    child: const Text('Учесть'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            checklist,
          ],
        ),
      ),
    );
  }
}
