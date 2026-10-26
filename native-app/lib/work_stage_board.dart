import 'package:flutter/material.dart';

import 'domain.dart';
import 'repository.dart';

const workStageLabels = {
  'note': 'Заметка',
  'planned': 'План · не начато',
  'active': 'В работе',
  'commissioning': 'Вводится в эксплуатацию',
  'ready': 'Готово к эксплуатации',
  'operation': 'В эксплуатации',
  'blocked': 'Препятствие',
  'retired': 'Выведено / отложено',
};
const stageColors = {
  'note': Color(0xfff1f1ee),
  'planned': Color(0xffefeeea),
  'active': Color(0xfffff1bd),
  'commissioning': Color(0xffd3f6de),
  'ready': Color(0xffe2f0e8),
  'operation': Color(0xffd8ecff),
  'blocked': Color(0xffffe2df),
  'retired': Color(0xffe8eaed),
};

String caseStage(Json item) => switch (item['status']) {
  'closed' => 'ready',
  'new' => 'planned',
  _ => 'active',
};
String caseStatusText(Json item) => switch (item['status']) {
  'closed' => 'Закрыт',
  'new' => 'Новый',
  'watching' => 'Наблюдение',
  'active' => 'В работе',
  _ => 'No Data',
};

class WorkStageBoard extends StatelessWidget {
  final DashboardRepository repo;
  final List<Json> entries;
  final Widget Function(Json, String) card;
  final void Function(String) create;
  const WorkStageBoard({
    super.key,
    required this.repo,
    required this.entries,
    required this.card,
    required this.create,
  });
  @override
  Widget build(BuildContext context) {
    final collapsed = object(repo.local.get('workStageCollapsed'));
    final stages = {
      ...workStageLabels,
      for (final entry in entries.where(
        (e) => !workStageLabels.containsKey(e['stage']),
      ))
        entry['stage'].toString(): 'Другая стадия · ${entry['stage']}',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final stage in stages.entries)
            Builder(
              builder: (context) {
                final items = entries
                    .where((e) => e['stage'] == stage.key)
                    .toList();
                final closed = collapsed[stage.key] as bool? ?? items.isEmpty;
                return Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: SizedBox(
                    width: closed ? 78 : 300,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Material(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Color.alphaBlend(
                                  (stageColors[stage.key] ?? Colors.grey)
                                      .withValues(alpha: .15),
                                  Theme.of(context)
                                      .colorScheme
                                      .surfaceContainer,
                                )
                              : stageColors[stage.key] ??
                                    const Color(0xffeeeeee),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            key: ValueKey('work-stage:${stage.key}'),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              repo.setUiPreference('workStageCollapsed', {
                                ...collapsed,
                                stage.key: !closed,
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: closed
                                  ? Column(
                                      children: [
                                        const Icon(Icons.chevron_right),
                                        Text(
                                          '${items.length}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        RotatedBox(
                                          quarterTurns: 1,
                                          child: Text(stage.value),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        const Icon(Icons.expand_more, size: 20),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            stage.value,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text('${items.length}'),
                                        IconButton(
                                          tooltip: 'Добавить · ${stage.value}',
                                          onPressed: () => create(stage.key),
                                          icon: const Icon(Icons.add, size: 19),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        if (!closed) ...[
                          const SizedBox(height: 12),
                          if (items.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Нет карточек'),
                            ),
                          for (final entry in items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: card(
                                object(entry['item']),
                                entry['ref'].toString(),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
