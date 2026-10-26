// Stable built-in IDs shared with lib/goal-grid.mjs.
const List<Map<String, dynamic>> defaultGoalColumns = [
  {"id": "title", "title": "Индикатор", "type": "text", "width": 400},
  {
    "id": "physicalSystem",
    "title": "Физическая система",
    "type": "text",
    "width": 240,
  },
  {"id": "unit", "title": "Единица / период", "type": "text", "width": 200},
  {
    "id": "current",
    "title": "Шкала/характеристика сейчас",
    "type": "computed",
    "width": 240,
  },
  {
    "id": "target",
    "title": "Предпочтительная мною шкала",
    "type": "number",
    "width": 240,
  },
  {"id": "delta", "title": "Изменение", "type": "computed", "width": 260},
  {"id": "dueDate", "title": "Дедлайн цели", "type": "date", "width": 200},
  {"id": "status", "title": "Статус цели", "type": "select", "width": 220},
];
