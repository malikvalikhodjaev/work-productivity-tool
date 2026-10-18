import 'domain.dart';

const alphaStateNames = {
  'empty': 'Пустой слот',
  'described': 'Описано',
  'working': 'В работе',
  'verified': 'Подтверждено',
  'ready': 'Готово к эксплуатации',
  'not_applicable': 'Не применяется',
};
const projectStatusNames = {
  'active': 'Активный',
  'paused': 'Приостановлен',
  'closed': 'Закрыт',
};
const projectPhaseNames = {
  'pre_operation': 'До эксплуатации',
  'operation': 'В эксплуатации',
};

String alphaName(Json alpha) {
  final name = (alpha['uniqueName'] ?? '').toString();
  return name.trim().isNotEmpty
      ? name
      : (alpha['typeName'] ?? 'Альфа').toString();
}

List<String> alphaIssues(
  Json alpha,
  List<Json> siblings, [
  Set<String>? ancestors,
]) {
  final id = alpha['id'].toString();
  final seen = {...?ancestors};
  if (!seen.add(id)) return ['Цикл подальф'];
  final issues = <String>[];
  bool missing(String key) => (alpha[key] ?? '').toString().trim().isEmpty;
  if (alpha['state'] == 'not_applicable') {
    if (missing('evidence')) issues.add('Не объяснено, почему не применяется');
  } else {
    if (missing('filledDate')) issues.add('Слот не заполнен');
    if (!['verified', 'ready'].contains(alpha['state'])) {
      issues.add('Состояние не подтверждено');
    }
    if (missing('criteria')) issues.add('Не задан критерий состояния');
    if (missing('evidence')) issues.add('Нет подтверждения');
  }
  if (siblings
      .where((a) => a['parentId'] == alpha['id'])
      .any((child) => alphaIssues(child, siblings, seen).isNotEmpty)) {
    issues.add('Подальфы требуют внимания');
  }
  return issues;
}

Json modelProject(Json project, List<Json> allAlphas) {
  final alphas = allAlphas
      .where((a) => a['projectId'] == project['id'])
      .toList();
  final zones = [
    for (final zone in rows(project['zones']))
      (() {
        final roots = alphas
            .where(
              (a) =>
                  a['zoneId'] == zone['id'] &&
                  (a['parentId'] ?? '').toString().isEmpty,
            )
            .toList();
        final issues = roots.isEmpty
            ? ['Нет слота альфы']
            : roots.expand((a) => alphaIssues(a, alphas)).toSet().toList();
        return <String, dynamic>{
          ...zone,
          'covered': roots.isNotEmpty && issues.isEmpty,
          'issues': issues,
          'slotCount': alphas.where((a) => a['zoneId'] == zone['id']).length,
        };
      })(),
  ];
  return {
    ...project,
    'zones': zones,
    'summary': {
      ...object(project['summary']),
      'slots': alphas.length,
      'filled': alphas
          .where((a) => (a['filledDate'] ?? '').toString().isNotEmpty)
          .length,
      'coveredZones': zones.where((z) => z['covered'] == true).length,
      'totalZones': zones.length,
      'gaps': zones.where((z) => z['covered'] != true).length,
    },
  };
}
