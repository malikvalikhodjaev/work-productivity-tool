import 'package:flutter/material.dart';

import 'domain.dart';
import 'forms.dart';
import 'goal_progress.dart';
import 'repository.dart';

class SystemsPanel extends StatelessWidget {
  final DashboardRepository repo;
  final void Function(Json?) configure;
  final void Function(Json, Json) measure;
  final VoidCallback openWork;
  const SystemsPanel({
    super.key,
    required this.repo,
    required this.configure,
    required this.measure,
    required this.openWork,
  });

  @override
  Widget build(BuildContext context) {
    final systems = repo.entities('systems', 'system');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionTitle(
          'Характеристики систем',
          trailing: TextButton(
            onPressed: () => configure(null),
            child: const Text('＋ Система'),
          ),
        ),
        const Text(
          'Здесь видно, что меняется в системе благодаря работе над проектом: какие характеристики улучшаются и какие ограничения важно соблюдать.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Чтобы появились данные: назови характеристику и единицу в настройках системы, затем нажми «Записать первый замер». Предпочтительное значение можно задать позднее. Следующие шаги и задачи записывай в «Работе».',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: openWork,
            icon: const Icon(Icons.view_kanban_outlined),
            label: const Text('Перейти к работам'),
          ),
        ),
        if (systems.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Системы пока не добавлены. Начни с одной, которую меняет твой проект.',
            ),
          ),
        for (final system in systems)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    system['name'].toString(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => configure(system),
                      icon: const Icon(Icons.tune),
                      label: const Text('Настроить характеристики'),
                    ),
                  ),
                  if (!rows(
                    system['characteristics'],
                  ).any((c) => (c['name'] ?? '').toString().trim().isNotEmpty))
                    const Text(
                      'Характеристики ещё не выбраны. В настройках можно назвать до трёх приоритетов и один ограничитель; заполняй только то, за чем сейчас хочешь наблюдать.',
                    ),
                  for (final source in rows(system['characteristics']).where(
                    (c) => (c['name'] ?? '').toString().trim().isNotEmpty,
                  ))
                    Builder(
                      builder: (context) {
                        final input = {
                          ...source,
                          'characteristicId': source['id'],
                        };
                        final current = evaluateGoal(
                          input,
                          goalMeasurements(repo, input),
                        );
                        final ready =
                            (source['unit'] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty &&
                            source['id'] is String;
                        final suffix = (source['unit'] ?? '').toString().isEmpty
                            ? ''
                            : ' ${source['unit']}';
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${source['kind'] == 'limit' ? 'Ограничитель · ' : ''}${source['name']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                current['current'] is num
                                    ? 'Сейчас: ${goalNumber(current['current'])}$suffix'
                                    : 'Замеров пока нет — запиши первое значение.',
                              ),
                              if (object(current['measurement'])['pending'] ==
                                  true)
                                const Text(
                                  'Замер сохранён на устройстве',
                                  style: TextStyle(fontSize: 12),
                                ),
                              Text(
                                source['target'] is num
                                    ? '${source['kind'] == 'limit' ? 'Не выше' : 'Предпочтительное значение'}: ${goalNumber(source['target'])}$suffix'
                                    : source['kind'] == 'limit'
                                    ? 'Ограничение пока не задано.'
                                    : 'Предпочтительное значение пока не задано.',
                              ),
                              if (!ready)
                                Text(
                                  (source['unit'] ?? '')
                                          .toString()
                                          .trim()
                                          .isEmpty
                                      ? 'Для замера сначала укажи единицу в настройках.'
                                      : 'Для первого замера нужно синхронизировать создание системы.',
                                ),
                              Wrap(
                                children: [
                                  TextButton.icon(
                                    key: ValueKey(
                                      'measure-system-characteristic:${source['id']}',
                                    ),
                                    onPressed: ready
                                        ? () => measure(system, current)
                                        : () => configure(system),
                                    icon: const Icon(Icons.add_chart),
                                    label: Text(
                                      !ready
                                          ? 'Уточнить характеристику'
                                          : current['current'] == null
                                          ? 'Записать первый замер'
                                          : 'Записать новый замер',
                                    ),
                                  ),
                                  if (rows(current['history']).isNotEmpty)
                                    TextButton(
                                      onPressed: () => showGoalHistory(
                                        context,
                                        {...current, 'title': source['name']},
                                      ),
                                      child: const Text('История замеров'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
