import 'package:flutter/material.dart';

class TableProgress extends StatelessWidget {
  final num done, planned;
  final String? pending;
  const TableProgress({
    super.key,
    required this.done,
    required this.planned,
    this.pending,
  });
  @override
  Widget build(BuildContext context) {
    final percent = planned > 0 ? (done * 100 / planned).round() : null;
    return Semantics(
      label: 'Выполнение норматива',
      value: '$done из $planned${percent == null ? '' : ', $percent%'}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$done / $planned${percent == null ? '' : ' · $percent%'}'),
          if (percent != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: (done / planned).clamp(0, 1).toDouble(),
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
              ),
            ),
          ],
          if (pending != null)
            Text(pending!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
