import 'domain.dart';

bool isGoalHierarchyConflict(Json item) {
  final body = object(item['body']);
  return item['state'] == 'conflict' &&
      body['module'] == 'workspace' &&
      body['action'] == 'moveGoal' &&
      (item['error'] ?? '').toString().startsWith(
        'Иерархия индикаторов уже изменилась.',
      );
}

const goalHierarchyConflictHelp =
    'Порядок или вложенность строк изменились. Повтор той же команды снова проверит прежнюю структуру и не устранит конфликт. Можно применить выбранный перенос к текущей структуре либо оставить серверный вариант. Исходная команда сохранится в истории.';
