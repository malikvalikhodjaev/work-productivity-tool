import 'focus_art_catalog.dart';

/// Device-local wall-clock schedule. It never writes timer or work records.
List<String> rotationPool(Map<String, dynamic> settings) {
  final available = focusArtworks.map((a) => a.id).toSet();
  final saved = settings['pool'];
  return saved is List
      ? saved.whereType<String>().where(available.contains).toSet().toList()
      : available.toList();
}

int rotationMinutes(Map<String, dynamic> settings) {
  final value = settings['minutes'];
  return value is int && value >= 1 && value <= 10080 ? value : 10;
}

String focusThemeAt(String manual, Map<String, dynamic> settings, int nowMs) {
  if (settings['enabled'] != true) return manual;
  final pool = rotationPool(settings);
  final anchor = settings['anchorMs'];
  if (pool.isEmpty || anchor is! int) return manual;
  final elapsed = nowMs > anchor ? nowMs - anchor : 0;
  final start = pool.indexOf(manual);
  return pool[((start < 0 ? 0 : start) +
          elapsed ~/ (rotationMinutes(settings) * 60000)) %
      pool.length];
}

Map<String, dynamic> restartRotation(
  Map<String, dynamic> settings, {
  required int nowMs,
}) => {...settings, 'anchorMs': nowMs};
