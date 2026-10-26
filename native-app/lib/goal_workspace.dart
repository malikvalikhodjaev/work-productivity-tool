import 'domain.dart';
import 'model_hierarchy.dart';

/// Filters are a projection only. Archive/trash boundaries are applied before
/// search, so an ancestor cannot silently bring an excluded branch back.
List<Json> filterGoalRows(
  List<Json> source, {
  String mode = 'current',
  String status = '',
  String? branchId,
}) {
  final ordered = hierarchyRows(source);
  final byId = {for (final g in ordered) g['id'].toString(): g};
  List<Json> lineage(Json goal) {
    final path = <Json>[];
    final seen = <String>{};
    Json? current = goal;
    while (current != null && seen.add(current['id'].toString())) {
      path.add(current);
      current = byId[parentOf(current)];
    }
    return path;
  }

  final eligible = <String, Json>{};
  for (final goal in ordered) {
    final path = lineage(goal);
    if (branchId != null && !path.any((g) => g['id'] == branchId)) continue;
    final trashed = path.any((g) => g['trashedAt'] != null);
    final archived = path.any((g) => g['status'] == 'archived');
    final allowed = switch (mode) {
      'trash' => trashed,
      'archived' => !trashed && archived,
      'all' => !trashed,
      _ => !trashed && !archived,
    };
    if (allowed) {
      eligible[goal['id'].toString()] = {
        ...goal,
        '_sourceWbs': goal['_wbs'],
        '_inTrash': trashed,
        '_inArchive': archived,
        '_trashOwner': path
            .where((g) => g['trashedAt'] != null)
            .lastOrNull?['id'],
        '_archiveOwner': path
            .where((g) => g['status'] == 'archived')
            .lastOrNull?['id'],
      };
    }
  }
  if (status.isEmpty) return eligible.values.toList();
  final keep = <String>{};
  for (final goal in eligible.values.where((g) => g['status'] == status)) {
    for (final parent in lineage(goal)) {
      if (eligible.containsKey(parent['id'])) keep.add(parent['id'].toString());
    }
  }
  return [
    for (final g in eligible.values)
      if (keep.contains(g['id'])) g,
  ];
}
