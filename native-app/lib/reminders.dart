import 'domain.dart';

// Schedule is anchored to the chosen daily time in the dashboard's +05:00 timezone.
int dueAt(Json norm, int utcNow, {int repeatMinutes = 60}) {
  final now = DateTime.fromMillisecondsSinceEpoch(
    utcNow,
    isUtc: true,
  ).add(const Duration(hours: 5));
  final days = (norm['days'] as List?) ?? [1, 2, 3, 4, 5, 6, 7];
  final parts = (norm['time'] ?? '09:00').toString().split(':');
  final anchor = DateTime.utc(
    now.year,
    now.month,
    now.day,
    int.parse(parts[0]),
    int.parse(parts[1]),
  ).subtract(const Duration(hours: 5)).millisecondsSinceEpoch;
  if (norm['enabled'] != true || !days.contains(now.weekday)) return -1;
  if (utcNow < anchor) return anchor;
  final interval = repeatMinutes * 60000;
  return anchor + ((utcNow - anchor) ~/ interval) * interval;
}

bool shouldShow(
  Json norm,
  int utcNow, {
  int? hiddenUntil,
  bool confirmed = false,
  double actualMinutes = 0,
  int repeatMinutes = 60,
}) {
  if (confirmed || actualMinutes >= (norm['minutes'] as num).toDouble()) {
    return false;
  }
  final due = dueAt(norm, utcNow, repeatMinutes: repeatMinutes);
  return due >= 0 &&
      due <= utcNow &&
      (hiddenUntil == null || utcNow >= hiddenUntil);
}

int nextReminder(Json norm, int utcNow, {int repeatMinutes = 60}) {
  final due = dueAt(norm, utcNow, repeatMinutes: repeatMinutes);
  return due > utcNow ? due : due + repeatMinutes * 60000;
}
