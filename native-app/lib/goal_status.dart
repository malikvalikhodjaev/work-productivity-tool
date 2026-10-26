const goalStatusOptions = {
  'note': 'Записана',
  'planned': 'Запланирована',
  'active': 'В работе',
  'blocked': 'Есть препятствие',
  'paused': 'На паузе',
  'commissioning': 'Внедряется',
  'ready': 'Достигнута',
  'operation': 'Поддерживается',
  'retired': 'Отложена',
  'archived': 'В архиве',
};

String goalStatusLabel(dynamic status) =>
    goalStatusOptions[status] ?? 'Заполнить';
