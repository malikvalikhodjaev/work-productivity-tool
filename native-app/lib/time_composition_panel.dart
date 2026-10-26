import 'package:flutter/material.dart';

import 'domain.dart';
import 'time_composition.dart';

const timeTypeColors = {
  'investment': Color(0xff7266a5),
  'productive': Color(0xff347558),
  'leisure': Color(0xff5486a3),
  'waste': Color(0xffb78235),
  'unclassified': Color(0xff8b9290),
};

Color compositionColor(dynamic type) =>
    timeTypeColors[type] ?? const Color(0xff596e85);

class TimeCompositionPanel extends StatefulWidget {
  final List<Json> entries, facts;
  final Map<String, Json> sessions;
  final List<String> days;
  final bool known;
  const TimeCompositionPanel({
    super.key,
    required this.entries,
    required this.facts,
    required this.sessions,
    required this.days,
    required this.known,
  });
  @override
  State<TimeCompositionPanel> createState() => _TimeCompositionPanelState();
}

class _TimeCompositionPanelState extends State<TimeCompositionPanel> {
  String? day;
  @override
  Widget build(BuildContext context) {
    final selected = widget.days.contains(day) ? day : null;
    final entries = widget.entries
        .where((e) => selected == null || e['date'] == selected)
        .toList();
    final facts = widget.facts
        .where((f) => selected == null || f['date'] == selected)
        .toList();
    final breakdown = timeComposition(entries, facts, widget.sessions);
    final seconds = breakdown.fold<double>(0, (n, e) => n + e['seconds']);
    final count = breakdown.fold<int>(0, (n, e) => n + (e['pomodoros'] as int));
    String number(num n) => n.toStringAsFixed(1).replaceAll('.', ',');
    String percent(dynamic n) => n == null ? '—' : '${number(n as num)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Сочетания типов показаны отдельными строками. В общем итоге время и помидорки считаются один раз.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Состав времени и помидорок',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('composition-day:${widget.days.join(',')}'),
          initialValue: selected ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Период состава'),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Вся выбранная неделя'),
            ),
            for (final d in widget.days)
              DropdownMenuItem(value: d, child: Text(d)),
          ],
          onChanged: (value) =>
              setState(() => day = value == '' ? null : value),
        ),
        const SizedBox(height: 10),
        Text(
          widget.known
              ? 'Всего учтено: ${number(seconds / 3600)} ч · $count помидорок'
              : 'записи ещё не загружены',
        ),
        if (seconds > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final e in breakdown.where((e) => e['seconds'] > 0))
                    Expanded(
                      flex: ((e['seconds'] as num) * 1000).round().clamp(
                        1,
                        1 << 53,
                      ),
                      child: ColoredBox(color: compositionColor(e['type'])),
                    ),
                ],
              ),
            ),
          ),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          primary: false,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Тип')),
              DataColumn(label: Text('Часы')),
              DataColumn(label: Text('Доля времени')),
              DataColumn(label: Text('Помидорки')),
              DataColumn(label: Text('Доля помидорок')),
            ],
            rows: [
              for (final e in breakdown)
                DataRow(
                  cells: [
                    DataCell(
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: compositionColor(e['type']),
                          ),
                          const SizedBox(width: 8),
                          Text(timeTypeLabel(e['type'])),
                        ],
                      ),
                    ),
                    DataCell(
                      Text(
                        widget.known
                            ? number(e['seconds'] / 3600)
                            : 'Не записано',
                      ),
                    ),
                    DataCell(Text(percent(e['percent']))),
                    DataCell(
                      Text(widget.known ? '${e['pomodoros']}' : 'Не записано'),
                    ),
                    DataCell(Text(percent(e['pomodoroPercent']))),
                  ],
                ),
            ],
          ),
        ),
        const Text(
          'Проценты рассчитаны от учтённого времени и отдельно от учтённых помидорок, не от 24 часов. План и лимит не входят в знаменатель. Пробелы в учёте не считаются Waste.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Investment — вложение в будущие возможности; Productive — работа на текущий результат; Leisure — намеренный отдых; Waste — твоя явная оценка потерянного времени. Обычная пауза без оценки остаётся «Без типа». Это рабочие ориентиры, а не автоматические жёсткие критерии.',
        ),
        const Text(
          'Тип выбирается в карточке работы или при запуске активности. Изменение карточки не перекрашивает историю; закрытые паузы и перерывы не создают рабочих помидорок.',
        ),
      ],
    );
  }
}
