import 'package:flutter/material.dart';

import 'domain.dart';
import 'repository.dart';

class WeeklyProblemCard extends StatefulWidget {
  final DashboardRepository repo;
  final Future<void> Function(String week) edit;
  const WeeklyProblemCard({super.key, required this.repo, required this.edit});
  @override
  State<WeeklyProblemCard> createState() => _WeeklyProblemCardState();
}

class _WeeklyProblemCardState extends State<WeeklyProblemCard> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final current = weekStart();
    final week = selected ?? current;
    final weeks = {
      current,
      ...repo.weeklyProblems.map((e) => e['week'].toString()),
    }.toList()..sort((a, b) => b.compareTo(a));
    final entry = repo.weeklyProblem(week);
    final reference = rows(repo.cache('references')['entries'])
        .where((e) => e['title'] == 'Marc Andreessen · главная проблема недели')
        .firstOrNull;
    return Card(
      key: const ValueKey('weekly-problem-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Главная проблема недели',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: week,
              isExpanded: true,
              items: weeks
                  .map(
                    (w) => DropdownMenuItem(
                      value: w,
                      child: Text(
                        '${weekRange(w)}${w == current ? ' · эта неделя' : ''}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => selected = value == current ? null : value),
            ),
            const Text(
              'The biggest problem of the week is…',
              style: TextStyle(color: Color(0xff727780)),
            ),
            const SizedBox(height: 8),
            SelectableText(
              (entry['text'] ?? 'No Data').toString(),
              style: const TextStyle(fontSize: 18, height: 1.5),
            ),
            if (repo.local.draft('weeklyProblem:$week') != null)
              const Text(
                'Сохранено на устройстве · ожидает синхронизации',
                style: TextStyle(fontSize: 12),
              ),
            TextButton(
              onPressed: () => widget.edit(week),
              child: const Text('Записать / уточнить'),
            ),
            const ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Как выбрать главное на неделю?',
                style: TextStyle(fontSize: 14),
              ),
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Какой разрыв сейчас сильнее всего мешает нужному результату? Какую систему и её характеристику важно изменить? Что будет иначе к концу недели и по какому факту я это проверю?',
                  ),
                ),
              ],
            ),
            if (reference != null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Референс · Marc Andreessen',
                  style: TextStyle(fontSize: 14),
                ),
                children: [
                  SelectableText(
                    (reference['originalText'] ?? reference['note'] ?? '')
                        .toString(),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Цитата прислана владельцем. Ссылка на первоисточник: No Data.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            if (rows(entry['revisions']).isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Предыдущие формулировки',
                  style: TextStyle(fontSize: 14),
                ),
                children: rows(entry['revisions']).reversed
                    .map(
                      (r) => ListTile(
                        title: SelectableText(r['text'].toString()),
                        subtitle: Text(r['updatedAt'].toString()),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class WeeklyProblemBanner extends StatelessWidget {
  final DashboardRepository repo;
  final bool compact;
  final VoidCallback? edit;
  const WeeklyProblemBanner({
    super.key,
    required this.repo,
    this.compact = false,
    this.edit,
  });
  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('weekly-problem-above-timer'),
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Главная проблема недели',
          style: TextStyle(fontSize: 12, color: Color(0xffd0dad5)),
        ),
        const SizedBox(height: 4),
        Text(
          repo.weeklyProblemText,
          style: const TextStyle(fontSize: 14, color: Colors.white),
        ),
        if (edit != null)
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
