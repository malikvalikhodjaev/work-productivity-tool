import 'domain.dart';

const characteristicTypes = {
  'indicator': 'Индикатор',
  'monitoring': 'Мониторинг',
  'guardrail': 'Ограничение (guardrail)',
};
const characteristicEditableFields = [
  'title',
  'unit',
  'physicalSystem',
  'baseline',
  'target',
  'direction',
  'dueDate',
  'status',
  'trashedAt',
  'parentId',
  'characteristicId',
  'workRef',
  'characteristicType',
];
void validateCharacteristicFields(Json input) {
  for (final entry in {
    'title': 200,
    'unit': 200,
    'physicalSystem': 2000,
  }.entries) {
    if (!input.containsKey(entry.key)) continue;
    final value = input[entry.key];
    if (value is! String ||
        value.length > entry.value ||
        entry.key == 'title' && value.trim().isEmpty) {
      throw FormatException(
        '${entry.key == 'unit'
            ? 'Единица и период'
            : entry.key == 'title'
            ? 'Название'
            : 'Физическая система'}: ${entry.key == 'title' ? 'заполни поле; ' : ''}до ${entry.value} символов.',
      );
    }
  }
  if (input.containsKey('characteristicType') &&
      input['characteristicType'] != null &&
      !characteristicTypes.containsKey(input['characteristicType'])) {
    throw const FormatException('Выбери тип характеристики.');
  }
}
