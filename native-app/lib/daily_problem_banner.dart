import 'package:flutter/material.dart';

import 'repository.dart';

class DailyProblemBanner extends StatelessWidget {
  final DashboardRepository repo;
  final bool compact;
  final VoidCallback? edit;
  const DailyProblemBanner({
    super.key,
    required this.repo,
    this.compact = false,
    this.edit,
  });

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('daily-problem-above-timer'),
    padding: EdgeInsets.all(compact ? 10 : 14),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: const Color(0x14ffffff),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Главная проблема на сегодня',
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Tooltip(
          message: repo.todayProblemText,
          child: Text(
            repo.todayProblemText,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 13 : 15,
              height: 1.4,
            ),
          ),
        ),
        if (edit != null && !compact)
          TextButton(
            onPressed: edit,
            child: const Text(
              'Записать / уточнить',
              style: TextStyle(color: Colors.white),
            ),
          ),
      ],
    ),
  );
}
