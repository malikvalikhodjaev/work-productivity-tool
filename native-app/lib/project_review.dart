import 'package:flutter/material.dart';

import 'domain.dart';
import 'repository.dart';

List<Json> reviewProjects(
  List<Json> projects,
  List<Json> alphas,
  String day,
) => [
  for (final project in projects.where((p) => p['status'] == 'active'))
    {
      'project': project,
      'zonesKnown':
          rows(project['zones']).isNotEmpty &&
          rows(project['zones']).every((z) => z['covered'] is bool),
      'zones': [
        for (final zone in rows(
          project['zones'],
        ).where((z) => z['covered'] == false))
          '${zone['title'] ?? zone['id']}: ${(zone['issues'] as List? ?? ['нужна диагностика']).join(', ')}',
      ],
      'alphas': [
        for (final alpha in alphas.where(
          (a) => a['projectId'] == project['id'],
        ))
          {
            'alpha': alpha,
            'due':
                (alpha['reviewDate'] ?? '').toString().isNotEmpty &&
                alpha['reviewDate'].toString().compareTo(day) <= 0,
            'reasons': [
              if ((alpha['reviewDate'] ?? '').toString().isEmpty)
                'не назначена дата возврата'
              else if (alpha['reviewDate'].toString().compareTo(day) <= 0)
                'пора вернуться · ${alpha['reviewDate']}',
              if ((alpha['evidence'] ?? '').toString().trim().isEmpty)
                'нет записанных свидетельств',
              if ((alpha['nextStep'] ?? '').toString().trim().isEmpty)
                'не записан следующий шаг',
              if ((alpha['uniqueName'] ?? '').toString().trim().isEmpty ||
                  alpha['uniqueName'] == alpha['typeName'])
                'не задано проектное имя',
            ],
          },
      ],
    },
];

class ProjectReview extends StatelessWidget {
  final DashboardRepository repo;
  final void Function(Json project, Json alpha) openAlpha;
  const ProjectReview({super.key, required this.repo, required this.openAlpha});

  @override
  Widget build(BuildContext context) {
    final entries = reviewProjects(
      repo.entities('projects', 'project'),
      repo.entities('alphas', 'alpha'),
      today(),
    );
    final due = entries
        .expand((e) => rows(e['alphas']))
        .where((a) => a['due'] == true)
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Регулярный обзор проектов',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Где не хватает проработки и к чему вернуться. Подсказки строятся по записям и датам в моделере.',
            ),
            const SizedBox(height: 10),
            if (repo.cache('portfolio').isEmpty)
              const Text('No Data · проекты ещё не загружены')
            else
              Text(
                'Активных проектов: ${entries.length} · альф к возврату: $due',
              ),
            for (final entry in entries)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(object(entry['project'])['name'].toString()),
                subtitle: Text(
                  '${entry['zonesKnown'] != true ? 'Зоны: No Data' : 'Зон с пробелами: ${(entry['zones'] as List).length}'} · альф к возврату: ${rows(entry['alphas']).where((a) => a['due'] == true).length}',
                ),
                children: [
                  if (rows(object(entry['project'])['zones']).isEmpty)
                    const ListTile(
                      title: Text('No Data · зоны проекта ещё не заданы'),
                    ),
                  for (final zone in entry['zones'] as List)
                    ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: Text(zone.toString()),
                    ),
                  if (rows(entry['alphas']).isEmpty)
                    const ListTile(
                      title: Text('No Data · в проекте пока нет альф'),
                    ),
                  for (final row in rows(entry['alphas']))
                    ListTile(
                      leading: Icon(
                        row['due'] == true
                            ? Icons.event_repeat
                            : Icons.account_tree_outlined,
                      ),
                      title: Text(
                        ((object(row['alpha'])['uniqueName'] ?? '')
                                    .toString()
                                    .trim()
                                    .isEmpty
                                ? object(row['alpha'])['typeName'] ?? 'Альфа'
                                : object(row['alpha'])['uniqueName'])
                            .toString(),
                      ),
                      subtitle: Text(
                        (row['reasons'] as List).isEmpty
                            ? 'Записи заполнены · возврат ${object(row['alpha'])['reviewDate']}'
                            : (row['reasons'] as List).join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openAlpha(
                        object(entry['project']),
                        object(row['alpha']),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
