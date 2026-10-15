import 'package:flutter/material.dart';

import 'domain.dart';
import 'forms.dart';
import 'repository.dart';

Future<void> chooseLeisure(
  BuildContext context,
  DashboardRepository repo,
) async {
  final session = repo.active;
  if (session == null || session['phase'] != 'work') return;
  final id = session['id'];
  final savedUntil = object(session['leisure'])['until'];
  final initial = DateTime.fromMillisecondsSinceEpoch(
    savedUntil is int && savedUntil > repo.now
        ? savedUntil
        : repo.now + 15 * 60000,
    isUtc: true,
  ).add(const Duration(hours: 5));
  final day = DateTime.fromMillisecondsSinceEpoch(
    repo.now,
    isUtc: true,
  ).add(const Duration(hours: 5));
  final dayOne = day.toIso8601String().substring(0, 10);
  final dayTwo = day
      .add(const Duration(days: 1))
      .toIso8601String()
      .substring(0, 10);
  await editFields(
    context,
    title: 'Leisure · до какого времени?',
    submitLabel: 'Начать отдых',
    progressLabel: 'Сохраняю…',
    initial: {
      'date': initial.toIso8601String().substring(0, 10),
      'time': initial.toIso8601String().substring(11, 16),
    },
    fields: [
      FieldSpec(
        'date',
        'День · Ташкент, UTC+5',
        options: {dayOne: 'Сегодня · $dayOne', dayTwo: 'Завтра · $dayTwo'},
      ),
      const FieldSpec('time', 'Время окончания · HH:mm'),
    ],
    save: (input) async {
      if (repo.active?['id'] != id) {
        throw StateError('Этот сеанс уже изменён. Открой текущий таймер.');
      }
      final text = input['time'].toString();
      if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(text)) {
        throw ArgumentError('Время: HH:mm, например 21:30.');
      }
      final until = DateTime.parse('${input['date']}T$text:00+05:00')
          .millisecondsSinceEpoch;
      await repo.timerAction('leisure', leisureUntil: until);
    },
  );
}

Future<void> askLeisureReturn(
  BuildContext context,
  DashboardRepository repo,
) async {
  final session = repo.active;
  if (!inLeisure(session)) return;
  final id = session!['id'];
  final proceed = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Вернуться к работе?'),
      content: Text(
        'Время Leisure закончилось.\n${session['title']}\n\nРабочий таймер остаётся на паузе до твоего нажатия.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Позже'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Вернуться к работе'),
        ),
      ],
    ),
  );
  if (proceed == true && repo.active?['id'] == id && inLeisure(repo.active)) {
    await repo.timerAction('resume');
  }
}

class LeisureInfo extends StatelessWidget {
  final Json session;
  final int now;
  const LeisureInfo({super.key, required this.session, required this.now});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      '${leisureDue(session, now) ? 'Пора вернуться к работе' : 'Leisure до ${leisureTime(session)}'}\nРабочий таймер на паузе · ${clockOf(session, now, workOnly: true)}\nLeisure: ${(leisureElapsedMs(session, now) / 60000).toStringAsFixed(1)} мин',
      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
    ),
  );
}
