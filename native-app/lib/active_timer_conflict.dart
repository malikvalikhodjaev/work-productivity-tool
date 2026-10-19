import 'domain.dart';

/// Starting another work never changes or accounts the current session.
class ActiveTimerConflict extends StateError {
  final String sessionId;
  final String title;
  final bool paused;
  ActiveTimerConflict(Json session)
    : sessionId = session['id'].toString(),
      title = (session['title'] ?? '').toString().trim().isEmpty
          ? 'Без названия'
          : session['title'].toString(),
      paused = session['status'] == 'paused',
      super(
        'Уже есть активный сеанс «${(session['title'] ?? '').toString().trim().isEmpty ? 'Без названия' : session['title']}»'
        '${session['status'] == 'paused' ? ' — на паузе' : ''}. '
        'Новая работа не запущена. Сначала заверши или отмени текущий сеанс.',
      );

  @override
  String toString() => message;
}
