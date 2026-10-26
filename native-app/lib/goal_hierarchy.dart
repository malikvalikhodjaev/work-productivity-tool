import 'dart:convert';

import 'domain.dart';
import 'model_hierarchy.dart';

String goalHierarchySignature(List<Json> items) {
  final sorted = [...items]
    ..sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));
  return jsonEncode([
    for (final r in sorted)
      [
        r['id'],
        parentOf(r),
        r['sortOrder'],
        r['status'] == 'archived',
        r['trashedAt'],
      ],
  ]);
}

/// A branch moves by its parent link. Its UUIDs, text and facts stay untouched.
List<Json> relocateGoal(List<Json> items, Json input) {
  final next = [for (final r in items) Map<String, dynamic>.from(r)];
  final byId = {for (final r in next) r['id'].toString(): r};
  final row = byId[input['id']];
  if (row == null) throw StateError('Строка не найдена.');
  final parentId = parentOf(input), oldParent = parentOf(row);
  void available(String? id, {bool checkCycle = false}) {
    final seen = <String>{if (checkCycle) row['id'].toString()};
    while (id != null) {
      if (!seen.add(id)) {
        throw StateError('Нельзя вложить строку в себя или потомка.');
      }
      final current = byId[id];
      if (current == null) throw StateError('Родитель не найден.');
      if (current['trashedAt'] != null || current['status'] == 'archived') {
        throw StateError('Сначала восстанови ветвь из архива или корзины.');
      }
      id = parentOf(current);
    }
  }

  available(row['id'].toString());
  available(parentId, checkCycle: true);
  final siblings = orderedSiblings(
    next,
    parentId,
  ).where((r) => r['id'] != row['id']).toList();
  final index = input['beforeId'] == null
      ? siblings.length
      : siblings.indexWhere((r) => r['id'] == input['beforeId']);
  if (index < 0) throw StateError('Место вставки уже изменилось.');
  if (input['beforeId'] != null) available(input['beforeId'].toString());
  siblings.insert(index, row);
  row['parentId'] = parentId;
  for (var i = 0; i < siblings.length; i++) {
    byId[siblings[i]['id']]!['sortOrder'] = i;
  }
  if (oldParent != parentId) {
    final previous = orderedSiblings(next, oldParent);
    for (var i = 0; i < previous.length; i++) {
      byId[previous[i]['id']]!['sortOrder'] = i;
    }
  }
  return next;
}

Json goalDropInput(
  List<Json> items,
  String id,
  Json? target,
  String placement,
) {
  if (target == null) return {'id': id, 'parentId': null, 'beforeId': null};
  final parentId = placement == 'inside'
      ? target['id'].toString()
      : parentOf(target);
  String? beforeId;
  if (placement == 'before') {
    beforeId = target['id'].toString();
  } else if (placement == 'after') {
    final siblings = orderedSiblings(
      items,
      parentId,
    ).where((r) => r['id'] != id).toList();
    final index = siblings.indexWhere((r) => r['id'] == target['id']);
    if (index < 0) throw StateError('Строка не найдена.');
    if (index + 1 < siblings.length) {
      beforeId = siblings[index + 1]['id'].toString();
    }
  }
  return {'id': id, 'parentId': parentId, 'beforeId': beforeId};
}
