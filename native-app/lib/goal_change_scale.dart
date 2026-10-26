import 'package:flutter/material.dart';

import 'domain.dart';
import 'goal_progress.dart';

num? _finite(dynamic value) => value is num && value.isFinite ? value : null;

/// Baseline is the left end even when the preferred value is smaller.
double? goalScaleRatio(Json goal) {
  final start =
      _finite(goal['comparisonBaseline']) ?? _finite(goal['baseline']);
  final current = _finite(goal['current']), target = _finite(goal['target']);
  if (start == null || current == null || target == null || start == target) {
    return null;
  }
  final ratio = (current - start) / (target - start);
  return ratio.isFinite ? ratio : null;
}

class GoalChangeScale extends StatelessWidget {
  final Json goal;
  final VoidCallback measure, configure;
  const GoalChangeScale({
    super.key,
    required this.goal,
    required this.measure,
    required this.configure,
  });

  @override
  Widget build(BuildContext context) {
    final start =
        _finite(goal['comparisonBaseline']) ?? _finite(goal['baseline']);
    final current = _finite(goal['current']), target = _finite(goal['target']);
    final ratio = goalScaleRatio(goal), scheme = Theme.of(context).colorScheme;
    final percent = ratio == null ? null : (ratio * 100).round();
    if (start == null && current == null && target == null) {
      return TextButton(
        onPressed: measure,
        child: const Text('Записать шкалу'),
      );
    }
    final unit = (goal['unit'] ?? '').toString();
    final description =
        'Начало: ${goalNumber(start)}. Сейчас: ${goalNumber(current)}. '
        'Предпочтительно: ${goalNumber(target)}${unit.isEmpty ? '' : '. $unit'}'
        '${percent == null ? '' : '. $percent% пути к предпочтительной шкале'}.';
    return Semantics(
      label: 'Шкала изменения',
      value: description,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Tooltip(
                message: 'Исходное значение: ${goalNumber(start)}',
                child: start == null
                    ? TextButton(
                        onPressed: measure,
                        child: const Text('Начало: Заполнить'),
                      )
                    : Text(
                        goalNumber(start),
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
              ),
              Tooltip(
                message: 'Предпочтительная мною шкала: ${goalNumber(target)}',
                child: target == null
                    ? TextButton(
                        onPressed: configure,
                        child: const Text('Предпочтительное: Заполнить'),
                      )
                    : Text(
                        goalNumber(target),
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
              ),
            ],
          ),
          if (ratio != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Tooltip(
                message: description,
                child: SizedBox(
                  height: 18,
                  width: double.infinity,
                  child: CustomPaint(
                    key: ValueKey('goal-scale-marker:${goal['id']}'),
                    painter: GoalScalePainter(
                      position: ratio.clamp(0, 1).toDouble(),
                      track: scheme.surfaceContainerHighest,
                      accent: scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: measure,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 4,
                  ),
                ),
                child: Text(
                  current == null
                      ? 'Сейчас: Записать замер'
                      : 'Сейчас: ${goalNumber(current)}',
                ),
              ),
              if (percent != null)
                Text(
                  '$percent%${goal['reached'] == true ? ' · достигнуто' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          if (start != null && target != null && start == target)
            Text(
              'Начало и предпочтительное совпадают',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (goal['delta'] is num)
            Text(
              'Δ ${goal['delta'] > 0 ? '+' : ''}${goalDifferenceNumber(goal['delta'])}${unit.isEmpty ? '' : ' $unit'}'
              '${goal['changePercent'] is num ? ' (${goal['changePercent'] > 0 ? '+' : ''}${goalNumber((goal['changePercent'] as num).round())}%)' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (goal['lastChange'] is num)
            Text(
              'К прошлому: ${goal['lastChange'] > 0 ? '+' : ''}${goalDifferenceNumber(goal['lastChange'])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class GoalScalePainter extends CustomPainter {
  final double position;
  final Color track, accent;
  const GoalScalePainter({
    required this.position,
    required this.track,
    required this.accent,
  });
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 12 || size.height < 12) return;
    final line = Rect.fromLTWH(6, size.height / 2 - 3, size.width - 12, 6);
    final x = 6 + (size.width - 12) * position;
    canvas.drawRRect(
      RRect.fromRectAndRadius(line, const Radius.circular(3)),
      Paint()..color = track,
    );
    if (position > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(6, line.top, x, line.bottom),
          const Radius.circular(3),
        ),
        Paint()..color = accent.withValues(alpha: .45),
      );
    }
    canvas.drawCircle(Offset(x, size.height / 2), 5.5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(GoalScalePainter oldDelegate) =>
      position != oldDelegate.position ||
      track != oldDelegate.track ||
      accent != oldDelegate.accent;
}
