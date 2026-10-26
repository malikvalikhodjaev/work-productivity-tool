const text = (id, title, maxLength = 4000, visible = false) => ({id, title, type:'text', maxLength, visible});
const select = (id, title, options, visible = false) => ({id, title, type:'select', options, visible});
const date = (id, title, visible = false) => ({id, title, type:'date', visible});
export const portfolioGridColumns = {
  projects: [
    {id:'_wbs',title:'Уровень',type:'computed',visible:true},
    select('parentId','Родительский проект',{'':'Верхний уровень'},true),
    {...text('name','Проект',120,true), required:true},
    select('status','Состояние',{active:'Активный',paused:'Приостановлен',closed:'Закрыт'},true),
    select('phase','Этап',{pre_operation:'До эксплуатации',operation:'В эксплуатации'},true),
    text('description','Заметки'), text('nextStep','Следующий шаг',1000), date('reviewDate','Вернуться'),
    {id:'_slots',title:'Слоты · заполнено / создано',type:'computed',visible:true},
    {id:'_gaps',title:'Зоны с пробелами',type:'computed',visible:true},
  ],
  alphas: [
    {id:'_wbs',title:'WBS',type:'computed',visible:true},
    text('uniqueName','Проектное имя',180,true), text('typeName','Типовое имя',120,true),
    select('state','Состояние',{empty:'Пустой слот',described:'Описано',working:'В работе',verified:'Подтверждено',ready:'Готово к эксплуатации',not_applicable:'Не применяется'},true),
    text('modelUrl','Ссылка на модель',4000,true),
    text('description','Описание и заметки'), text('criteria','Критерий состояния'),
    text('evidence','Свидетельства'), text('nextStep','Следующий шаг',1000,true),
    date('reviewDate','Вернуться',true), date('filledDate','Дата заполнения'),
    text('stateLabel','Состояние по шаблону',160), text('area','Интересующий предмет',180),
    text('whyImportant','Почему важно / чей интерес'), text('adaptedAlpha','Адаптированная альфа',180),
    text('source','Источник',2000), text('metaAdaptation','Адаптация модели'),
    text('systemTime','Время системы',100), text('attention','Внимание',100),
  ],
};

export function gridColumns(portfolio, table, {archived = false} = {}) {
  if (!portfolioGridColumns[table]) throw new Error('Неизвестная таблица.');
  return [...portfolioGridColumns[table], ...(portfolio.tableColumns?.[table] ?? [])]
    .filter(column => archived || !column.archived)
    .map(column => table === 'projects' && column.id === 'parentId' ? {...column, options:{'':'Верхний уровень',...Object.fromEntries(portfolio.projects.map(p => [p.id,p.name]))}} : column);
}

export function gridCellValue(row, column) {
  if (column.custom) return row.customValues?.[column.id] ?? null;
  if (column.id === '_slots') return `${row.summary?.filled ?? 0} / ${row.summary?.slots ?? 0}`;
  if (column.id === '_gaps') return row.summary?.totalZones ? `${row.summary.gaps} / ${row.summary.totalZones}` : null;
  if (column.id === '_wbs') return row._wbs ?? null;
  return row[column.id] ?? null;
}

export function gridCellText(row, column) {
  const value = gridCellValue(row,column);
  if (column.id === 'parentId' && (value === null || value === '')) return 'Верхний уровень';
  if (value === null || value === '') return 'No Data';
  if (column.type === 'checkbox') return value ? '✓' : '—';
  return column.options?.[value] ?? String(value);
}

export function visibleGridColumns(columns, view = {}) {
  const saved = Array.isArray(view.order) ? view.order : [];
  const hidden = new Set(view.hidden ?? []);
  const map = new Map(columns.map(column => [column.id,column]));
  const order = [...saved.filter(id => map.has(id)), ...columns.map(c=>c.id).filter(id=>!saved.includes(id))];
  const selected = order.filter(id=>!hidden.has(id) && (saved.includes(id) || map.get(id).visible || map.get(id).custom));
  return (selected.length ? selected : ['name','uniqueName'].filter(id=>map.has(id))).map(id=>({...map.get(id),title:view.labels?.[id] ?? map.get(id).title}));
}
