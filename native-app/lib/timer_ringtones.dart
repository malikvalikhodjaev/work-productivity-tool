import 'dart:async';

import 'package:flutter/material.dart';

import 'repository.dart';

const timerRingtones = <String, (String, String)>{
  'bip_bip': ('Бип-бип', 'Две пары коротких мягких импульсов'),
  'sonar': ('Сонар', 'Три округлых сигнала с паузами'),
  'glass': ('Стекло', 'Светлый звон из трёх нот'),
  'marimba': ('Маримба', 'Четыре тёплые деревянные ноты'),
  'orbit': ('Орбита', 'Спокойный восходящий и ответный мотив'),
  'warm_bell': ('Тёплый колокол', 'Два мягких удара с затуханием'),
  'classic': ('Прежний сигнал', 'Короткий однотонный сигнал'),
};
String validRingtone(dynamic id) =>
    timerRingtones.containsKey(id) ? id as String : 'bip_bip';
double validRingtoneVolume(dynamic value) =>
    value is num && value.isFinite ? value.toDouble().clamp(0, 1) : .65;
String ringtoneAsset(dynamic id) => validRingtone(id) == 'classic'
    ? 'audio/alarm.wav'
    : 'audio/ringtones/${validRingtone(id)}.wav';

class TimerRingtoneLibrary extends StatefulWidget {
  final DashboardRepository repo;
  final Future<void> Function(String id, double volume) preview;
  final Future<void> Function() stop;
  final Future<void> Function()? systemSettings;
  final VoidCallback changed;
  const TimerRingtoneLibrary({
    super.key,
    required this.repo,
    required this.preview,
    required this.stop,
    required this.changed,
    this.systemSettings,
  });
  @override
  State<TimerRingtoneLibrary> createState() => _TimerRingtoneLibraryState();
}

class _TimerRingtoneLibraryState extends State<TimerRingtoneLibrary> {
  late String selected;
  late double volume;
  String? message;
  @override
  void initState() {
    super.initState();
    selected = validRingtone(widget.repo.local.get('timerRingtone'));
    volume = validRingtoneVolume(widget.repo.local.get('timerRingtoneVolume'));
  }

  void save() {
    widget.repo.local.set('timerRingtone', selected);
    widget.repo.local.set('timerRingtoneVolume', volume);
    widget.changed();
  }

  Future<void> play(String id) async {
    try {
      await widget.preview(id, volume);
      if (mounted) {
        setState(() => message = 'Прослушивание: ${timerRingtones[id]!.$1}');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Не удалось воспроизвести сигнал. Проверь громкость устройства.',
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(widget.stop().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Библиотека рингтонов'),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Выбран: ${timerRingtones[selected]!.$1}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Text(
              'Сигнал окончания помидорки, перерыва и Leisure. Можно прослушать любой вариант перед выбором.',
            ),
            for (final entry in timerRingtones.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                selected: selected == entry.key,
                leading: Icon(
                  selected == entry.key
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(entry.value.$1),
                subtitle: Text(entry.value.$2),
                onTap: () => setState(() {
                  selected = entry.key;
                  save();
                  message = 'Выбор сохранён';
                }),
                trailing: IconButton(
                  tooltip: 'Прослушать: ${entry.value.$1}',
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: () => play(entry.key),
                ),
              ),
            Text('Громкость сигнала · ${(volume * 100).round()}%'),
            Slider(
              value: volume,
              divisions: 20,
              label: '${(volume * 100).round()}%',
              onChanged: (v) => setState(() => volume = v),
              onChangeEnd: (_) => save(),
            ),
            Text(
              widget.systemSettings == null
                  ? 'Громкость отдельна от фонового звука. Выбор сохраняется на этом устройстве.'
                  : 'Эта громкость — для прослушивания и открытого приложения. Фоновый сигнал использует громкость уведомлений Android. Выбор сохраняется на этом устройстве.',
              style: const TextStyle(fontSize: 12),
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message!),
              ),
            if (widget.systemSettings != null)
              TextButton(
                onPressed: () async {
                  try {
                    await widget.systemSettings!();
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => message = 'Открой настройки уведомлений Indicators & Work в Android.',
                      );
                    }
                  }
                },
                child: const Text('Настройки фонового сигнала Android'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => widget.stop(), child: const Text('Стоп')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Готово'),
      ),
    ],
  );
}
