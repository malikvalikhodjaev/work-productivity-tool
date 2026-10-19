import 'dart:convert';

import 'domain.dart';

String? parentOf(Json row) => row['parentId'] == null || row['parentId'] == ''
    ? null
    : row['parentId'].toString();
List<Json> orderedSiblings(List<Json> items, [String? parentId]) {
  final indexed = [
    for (var i = 0; i < items.length; i++) {'row': items[i], 'index': i},
  ];
  final selected = indexed
      .where((x) => parentOf(object(x['row'])) == parentId)
      .toList();
  selected.sort((a, b) {
    final ar = object(a['row']), br = object(b['row']);
    final order = ((ar['sortOrder'] as num?) ?? a['index'] as int).compareTo(
      (br['sortOrder'] as num?) ?? b['index'] as int,
    );
    return order != 0
        ? order
        : (a['index'] as int).compareTo(b['index'] as int);
  });
  return selected.map((x) => object(x['row'])).toList();
}

String hierarchySignature(List<Json> items) {
  final sorted = [...items]
    ..sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));
  return jsonEncode([
    for (final r in sorted) [r['id'], parentOf(r), r['sortOrder'], r['zoneId']],
  ]);
}

List<Json> hierarchyRows(List<Json> items, {Set<String> collapsed = const {}}) {
  final result = <Json>[],
      seen = <String>{},
      ids = items.map((r) => r['id']).toSet();
  void visit(Json row, String path, int depth, [bool hidden = false]) {
    if (!seen.add(row['id'].toString())) return;
    final children = orderedSiblings(items, row['id'].toString());
    if (!hidden) {
      result.add({
        ...row,
        '_wbs': path,
        '_depth': depth,
        '_hasChildren': children.isNotEmpty,
      });
    }
    for (var i = 0; i < children.length; i++) {
      visit(
        children[i],
        '$path.${i + 1}',
        depth + 1,
        hidden || collapsed.contains(row['id']),
      );
    }
  }

  final roots = [
    ...orderedSiblings(items),
    ...items.where((r) => parentOf(r) != null && !ids.contains(parentOf(r))),
  ];
  for (var i = 0; i < roots.length; i++) {
    visit(roots[i], '${i + 1}', 0);
  }
  for (final row in items) {
    if (!seen.contains(row['id'])) visit(row, '${result.length + 1}', 0);
  }
  return result;
}

List<Json> relocateAlpha(List<Json> items, Json input) {
  final next = items.map((r) => Map<String, dynamic>.from(r)).toList();
  final row = next.where((r) => r['id'] == input['id']).firstOrNull;
  if (row == null) throw StateError('Строка не найдена.');
  final parentId = parentOf(input),
      oldParent = parentOf(row),
      parent = next.where((r) => r['id'] == parentId).firstOrNull;
  if (parentId != null && parent == null) {
    throw StateError('Родитель не найден.');
  }
  if (parent != null && parent['projectId'] != row['projectId']) {
    throw StateError('Родитель должен быть в том же проекте.');
  }
  final seen = {row['id']};
  Json? ancestor = parent;
  while (ancestor != null) {
    if (!seen.add(ancestor['id'])) {
      throw StateError('Нельзя вложить строку в себя или потомка.');
    }
    final id = ancestor['parentId'];
    ancestor = next.where((r) => r['id'] == id).firstOrNull;
  }
  final siblings = orderedSiblings(
    next,
    parentId,
  ).where((r) => r['id'] != row['id']).toList();
  final index = input['beforeId'] == null
      ? siblings.length
      : siblings.indexWhere((r) => r['id'] == input['beforeId']);
  if (index < 0) throw StateError('Место вставки уже изменилось.');
  siblings.insert(index, row);
  row['parentId'] = parentId;
  if (parent != null) row['zoneId'] = parent['zoneId'];
  void moveZone(String id) {
    for (final child in next.where((r) => r['parentId'] == id)) {
      child['zoneId'] = row['zoneId'];
      moveZone(child['id'].toString());
    }
  }

  moveZone(row['id'].toString());
  for (var i = 0; i < siblings.length; i++) {
    siblings[i]['sortOrder'] = i;
  }
  if (oldParent != parentId) {
    final previous = orderedSiblings(next, oldParent);
    for (var i = 0; i < previous.length; i++) {
      previous[i]['sortOrder'] = i;
    }
  }
  return next;
}

Json sourceProjectDefinition(Json project, List<Json> alphas) => {
  'id': project['id'],
  'version': project['copyVersion'],
  'capturedAt': project['updatedAt'],
  'areas': rows(project['zones']),
  'sources': object(object(project['templateOrigin'])['sources']),
  'alphas': [
    for (final a in alphas)
      {
        'sourceId': a['id'],
        'parentId': parentOf(a),
        'areaId': a['zoneId'],
        'typeName': (a['typeName'] ?? '').toString().isNotEmpty
            ? a['typeName']
            : a['uniqueName'],
        'sortOrder': a['sortOrder'],
        'states': a['templateStates'] ?? [],
        'questions': a['templateQuestions'] ?? [],
        'source': a['source'] ?? '',
      },
  ],
};
Json materializeProject(Json definition, Json input) {
  final allAreas = rows(definition['areas']),
      selected =
          (input['areaIds'] as List? ?? allAreas.map((a) => a['id']).toList())
              .toSet();
  final areas = allAreas.where((a) => selected.contains(a['id'])).toList(),
      nodes = rows(definition['alphas'])
          .where((a) => selected.contains(a['areaId']))
          .toList(),
      ids = object(input['alphaIds']);
  final origin = {
    'id': definition['id'],
    'version': definition['version'],
    'capturedAt': definition['capturedAt'],
    'sources': object(definition['sources']),
    'areaIds': selected.toList(),
  };
  final project = <String, dynamic>{
    'id': input['clientId'],
    'name': input['name'],
    'status': 'active',
    'phase': 'pre_operation',
    'zones': [
      for (final a in areas)
        {
          'id': a['id'],
          'title': a['title'],
          'hint': a['hint'] ?? '',
          'typeName': a['typeName'] ?? a['title'],
        },
    ],
    'templateOrigin': origin,
    'revision': 1,
    'pendingCopy': true,
  };
  final alphas = <Json>[
    for (var i = 0; i < nodes.length; i++)
      (() {
        final node = nodes[i];
        return <String, dynamic>{
          'id': ids[node['sourceId']],
          'projectId': project['id'],
          'parentId': ids[node['parentId']],
          'zoneId': node['areaId'],
          'typeName': node['typeName'],
          'uniqueName': '',
          'description': '',
          'state': 'empty',
          'stateLabel': '',
          'criteria': '',
          'evidence': '',
          'nextStep': '',
          'filledDate': null,
          'reviewDate': null,
          'area': areas.firstWhere((a) => a['id'] == node['areaId'])['title'],
          'sortOrder': node['sortOrder'] ?? i,
          'source':
              node['source'] ??
              object(definition['sources'])['catalog'] ??
              object(definition['sources'])['template'] ??
              '',
          'templateStates': node['states'] ?? [],
          'templateQuestions': node['questions'] ?? [],
          'templateOrigin': {...origin, 'sourceRowId': node['sourceId']},
          'revision': 1,
          'pendingCopy': true,
        };
      })(),
  ];
  return {'project': project, 'alphas': alphas};
}
