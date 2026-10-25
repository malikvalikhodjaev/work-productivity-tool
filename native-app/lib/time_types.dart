const timeTypeLabels = {
  'investment': 'Investment · развитие',
  'productive': 'Productive · результат',
  'leisure': 'Leisure · отдых',
  'waste': 'Waste · потерянное',
  'unclassified': 'Без типа',
};
String _singleType(String value) => switch (value.trim().toLowerCase()) {
  'investment' ||
  'investment time' ||
  'инвестиционное' ||
  'инвестиции' => 'investment',
  'productive' || 'productive time' || 'продуктивное' => 'productive',
  'leisure' || 'leasure' || 'leisure time' || 'отдых' => 'leisure',
  'waste' || 'wasted' || 'wasted time' || 'потерянное' => 'waste',
  _ => 'unclassified',
};
List<String> timeTypes(dynamic value) {
  final raw = value?.toString() ?? '';
  if (raw.trim().isEmpty) return [];
  final parts = raw.split('+').map(_singleType).toSet();
  if (parts.contains('unclassified')) return [];
  return [
    for (final key in timeTypeLabels.keys)
      if (parts.contains(key)) key,
  ];
}

String encodeTimeTypes(Iterable<String> types) => [
  for (final key in timeTypeLabels.keys)
    if (key != 'unclassified' && types.contains(key)) key,
].join('+');
String timeType(dynamic value) {
  final types = timeTypes(value);
  return types.isEmpty ? 'unclassified' : encodeTimeTypes(types);
}

String timeTypeLabel(dynamic value) {
  final types = timeTypes(value);
  return types.isEmpty
      ? timeTypeLabels['unclassified']!
      : types.length == 1
      ? timeTypeLabels[types.single]!
      : types.map((t) => timeTypeLabels[t]!.split(' · ').first).join(' + ');
}

bool validTimeTypeSelection(dynamic value) {
  if (value is! String) return false;
  if (value.isEmpty) return true;
  final parts = value.split('+');
  return parts.length <= 4 &&
      parts.toSet().length == parts.length &&
      parts.every((p) => timeTypeLabels.containsKey(p) && p != 'unclassified');
}

Map<String, String> timeTypeOptions(dynamic previous) => {
  '': 'Не выбран',
  for (final e in timeTypeLabels.entries.where((e) => e.key != 'unclassified'))
    e.key: e.value,
  if (previous is String && previous.isNotEmpty && timeTypes(previous).isEmpty)
    previous: 'Прежний тип · $previous',
};
