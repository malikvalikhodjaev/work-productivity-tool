const $ = id => document.getElementById(id);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const nf = new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 2 });
const n = value => value === null || value === undefined ? 'No Data' : nf.format(value);
const types = { system: 'Система', case: 'Кейс', project: 'Проект', task: 'Задача', alpha: 'Альфа' };
const caseStatus = { new: 'Новый', active: 'В работе', watching: 'Наблюдение', closed: 'Закрыт' };
let workspace = null, activity = null, finance = null, period = '7d', loadId = 0, financeId = 0, submitAction = null;
let financeImport = null, activeTable = 'systems';
async function api(url, data, method = 'POST') {
  const response = await fetch(url, data === undefined ? {} : { method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || 'Не удалось сохранить данные.');
  return result;
}
function heading(title, subtitle, actions = '') { return `<div class="section-heading"><div><h2>${title}</h2><p class="section-note">${subtitle}</p></div><div class="workspace-actions">${actions}</div></div>`; }
function button(title, action, id = '', primary = false) { return `<button type="button" class="button ${primary ? 'primary' : 'secondary'}" data-w-action="${action}" data-id="${esc(id)}">${title}</button>`; }
function empty(text) { return `<div class="workspace-empty"><strong>No Data</strong><p>${text}</p></div>`; }
function table(headers, rows) { return `<div class="workspace-table-scroll"><table class="workspace-table"><thead><tr>${headers.map(h => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.length ? rows.map(row => `<tr>${row.map(cell => `<td>${cell}</td>`).join('')}</tr>`).join('') : `<tr><td colspan="${headers.length}">No Data</td></tr>`}</tbody></table></div>`; }
function workTitle(ref) { const item = workspace?.entities.find(e => e.ref === ref); return item ? `${types[item.type]} · ${item.title}` : 'No Data'; }
function bars(rows, total) { return rows.length ? rows.map(row => `<div class="time-bar"><div><span>${esc(row.title)}</span><strong>${n(row.hours)} ч</strong></div><div class="time-track"><i style="width:${total ? Math.min(100, row.hours / total * 100) : 0}%"></i></div></div>`).join('') : '<p class="section-note">No Data</p>'; }
function renderTime() {
  if (!activity) return;
  const time = activity.time;
  $('time-insight').innerHTML = heading('Куда уходит время', `${activity.start} — ${activity.end} · только учтённые часы`)
    + `<div class="time-total"><strong>${n(time.total)}</strong><span>часов учтено · ${time.records} записей</span></div><div class="time-breakdowns"><article class="workspace-card"><h3>Отношение к нормативам</h3>${bars(time.byAllocation, time.total)}</article><article class="workspace-card"><h3>Характер работ</h3>${bars(time.byWorkType, time.total)}</article></div><p class="section-note">«Вне нормативов» — осознанно отдельное время. «Без норматива» — направление есть, план на ту неделю не задан. Старые записи без характера работы остаются в «Не разобрано». Неучтённое время дня неизвестно.</p><details class="time-detail"><summary>Какие работы делал · ${time.records}</summary>${table(['Дата', 'Работа', 'Часы', 'Направление', 'Характер', 'Связь', ''], time.entries.map(e => [esc(e.date), esc(e.title || 'No Data'), n(e.amount), esc(e.direction), esc(e.workType), esc(workTitle(e.workRef)), `<button class="text-button" data-w-action="classify" data-id="${esc(e.id)}">Разобрать</button>`]))}</details>`;
}
function tile(c, note = '', compact = false) {
  const limit = c.kind === 'limit';
  const status = limit ? (c.violation === null ? 'No Data' : c.violation ? 'Превышен предел' : 'В пределах') : (c.reached === null ? 'No Data' : c.reached ? 'Цель достигнута' : 'До цели');
  return `<article class="characteristic ${limit ? 'limit' : ''} ${c.violation ? 'violated' : ''}"><span class="characteristic-kind">${limit ? 'ОГРАНИЧИТЕЛЬ · НЕ ВЫШЕ' : c.direction === 'up' ? 'ПРИОРИТЕТ · ↑' : 'ПРИОРИТЕТ · ↓'}</span><h4>${esc(c.name || 'No Data')}</h4><div class="characteristic-value"><strong>${n(c.current)}</strong><span>${esc(c.unit)}</span></div><div class="characteristic-target">${limit ? 'Предел' : 'Цель'}: ${n(c.target)} ${esc(c.unit)}</div><div class="characteristic-base">База: ${n(c.baseline)} · ${esc(c.measurement?.date || 'No Data')}</div><div class="characteristic-base">Δ от базы: ${c.current === null || c.baseline === null ? 'No Data' : (c.current - c.baseline > 0 ? '+' : '') + n(c.current - c.baseline)} ${esc(c.unit)}</div><span class="characteristic-status">${status}</span>${note ? `<p class="expected-impact">Ожидаем: ${esc(note)}</p>` : ''}${!compact && c.name ? `<button class="text-button" data-w-action="measure-characteristic" data-id="${c.id}">＋ Замер</button>` : ''}${c.measurement?.evidence && !compact ? `<details><summary>Подтверждение</summary><p>${esc(c.measurement.evidence)}</p></details>` : ''}</article>`;
}
function linked(ref) {
  if (ref.startsWith('system:')) return { system: workspace.systems.find(s => `system:${s.id}` === ref), notes: {} };
  const own = workspace.links.find(l => l.ownerRef === ref);
  const parentRef = workspace.entities.find(e => e.ref === ref)?.parentRef;
  const link = own ?? workspace.links.find(l => l.ownerRef === parentRef);
  return link ? { system: workspace.systems.find(s => s.id === link.systemId), notes: own?.notes ?? {}, inherited: !own } : {};
}
function renderImpacts() {
  if (!workspace) return;
  document.querySelectorAll('[data-impact-ref]').forEach(host => {
    const ref = host.dataset.impactRef, link = linked(ref);
    host.innerHTML = `<div class="impact-heading"><span>${link.system ? `${esc(link.system.name)}${link.inherited ? ' · связь проекта' : ''}` : 'Изменяемая система · No Data'}</span><button type="button" class="text-button" data-w-action="link" data-id="${esc(ref)}">${link.system ? 'Влияние / связь' : 'Связать'}</button></div>`
      + `<div class="characteristic-grid compact">${link.system ? link.system.characteristics.map(c => tile(c, link.notes[c.id], true)).join('') : [1,2,3,4].map(i => `<div class="characteristic"><span class="characteristic-kind">${i < 4 ? `ПРИОРИТЕТ ${i}` : 'ОГРАНИЧИТЕЛЬ'}</span><strong>No Data</strong></div>`).join('')}</div>`
      + (link.system ? '<p class="impact-caption">Факт — последние замеры системы. Влияние этой работы — ожидание до проверки результата.</p>' : '');
  });
}
function renderSystems() {
  $('systems-overview').innerHTML = heading('Системы и характеристики', 'Три главных изменения + ограничитель. Один замер виден во всех связанных работах.', button('＋ Система', 'system', '', true))
    + (workspace.systems.length ? workspace.systems.map(s => `<article class="system-card">${heading(esc(s.name), esc(s.description || 'Описание пока не задано'), button('Настроить', 'system', s.id))}<div class="characteristic-grid">${s.characteristics.map(c => tile(c)).join('')}</div></article>`).join('') : empty('Создай систему и задай, что в ней должно измениться. Значения появятся после замеров.'));
}
function renderGoals() {
  const goals = workspace.goals.filter(g => g.status === 'active');
  const otherGoals = workspace.goals.filter(g => g.status !== 'active');
  $('goal-overview').innerHTML = heading('Мои цели', 'Выбранные активные цели · прогресс по последнему замеру', button('＋ Цель', 'goal'))
    + (goals.length ? `<div class="result-grid">${goals.map(g => `<article class="workspace-card goal-result"><div class="result-card-heading"><h3>${esc(g.title)}</h3><span class="status-pill ${g.reached ? 'confirmed' : ''}">${g.status === 'paused' ? 'Пауза' : g.reached === null ? 'No Data' : g.reached ? 'Достигнута' : 'В работе'}</span></div><div class="goal-result-value">${n(g.current)} <small>/ ${n(g.target)} ${esc(g.unit)}</small></div><p class="section-note">${g.direction === 'up' ? 'Увеличить' : 'Уменьшить'} · база ${n(g.baseline)} · срок ${esc(g.dueDate || 'No Data')}</p><div class="time-track ${g.percent === null ? 'no-data' : ''}" role="progressbar" aria-label="${esc(g.title)}" aria-valuemin="0" aria-valuemax="100" ${g.percent === null ? 'aria-valuetext="No Data"' : `aria-valuenow="${g.percent}" aria-valuetext="${g.percent}%"`}><i style="width:${g.percent ?? 0}%"></i></div><p class="section-note">${g.percent === null ? 'No Data · нужен замер, база и цель' : `${g.percent}% от базы к цели`} · замер ${esc(g.measurement?.date || 'No Data')}</p>${g.systemName ? `<p class="section-note">Система: ${esc(g.systemName)}</p>` : ''}${g.workRef ? `<p class="section-note">${esc(workTitle(g.workRef))}</p>` : ''}<div class="workspace-actions">${button('Настроить', 'goal', g.id)}${button('＋ Замер', g.characteristicId ? 'measure-characteristic' : 'measure-goal', g.characteristicId || g.id)}</div></article>`).join('')}</div>` : '<p class="goal-empty">No Data · активные измеримые цели пока не заданы. Добавь свою цель и числовой ориентир.</p>')
    + (otherGoals.length ? `<details class="section-fold"><summary>Остальные цели · ${otherGoals.length}</summary><div class="section-fold-body goal-selection">${otherGoals.map(g=>`<div><span>${esc(g.title)} · ${g.status === 'paused' ? 'На паузе' : 'В архиве'}</span>${button('Настроить', 'goal', g.id)}</div>`).join('')}</div></details>` : '');
}
function renderCases() {
  const active = workspace.cases.filter(c => c.status !== 'closed');
  const withoutReview = active.filter(c => !c.review).length, overdue = active.filter(c => c.overdue).length;
  $('cases-overview').innerHTML = heading('Кейсы и диагностика', `${active.length} открыто · ${withoutReview} без диагностики · ${overdue} просрочено · ${active.filter(c => !c.nextStep).length} без следующего хода`, button('＋ Кейс', 'case'))
    + (workspace.cases.length ? workspace.cases.map(c => `<article class="workspace-card case-card"><div class="result-card-heading"><h3>${esc(c.title)}</h3><span class="status-pill ${c.overdue ? 'warning' : ''}">${caseStatus[c.status]}${c.overdue ? ' · пора проверить' : ''}</span></div><p>${esc(c.context || 'No Data')}</p><p class="section-note">Следующий ход: ${esc(c.nextStep || 'No Data')} · вернуться ${esc(c.nextReview || 'No Data')}</p>${c.resolution ? `<p>Результат: ${esc(c.resolution)}</p>` : ''}<div data-impact-ref="case:${c.id}"></div><div class="workspace-actions">${button('Настроить', 'case', c.id)}${button('Диагностика', 'review', c.id)}<button type="button" class="button secondary" data-timer-work="case:${c.id}" data-timer-title="${esc(c.title)}">◷ Таймер</button></div><details><summary>История диагностик</summary>${workspace.reviews.filter(r => r.caseId === c.id).map(r => `<p><strong>${esc(r.date)}</strong> · ${esc(r.facts)}<br>Неизвестно: ${esc(r.unknowns || 'No Data')}<br>Далее: ${esc(r.nextStep)}</p>`).join('') || '<p>No Data</p>'}</details></article>`).join('') : empty('Кейс — ситуация с контекстом, неизвестным и следующим ходом. Проект необязателен.'));
}
function renderFinance() {
  if (!finance) return;
  $('finance-overview').innerHTML = heading('Деньги', `${finance.start} — ${finance.end} · по учтённым операциям`, button('＋ Операция', 'transaction') + button('Импорт CSV', 'import', '', true))
    + (finance.currencies.length ? finance.currencies.map(c => `<article class="workspace-card currency-card"><h3>${esc(c.currency)}</h3><div class="money-grid"><div><span>Приток</span><strong>${n(c.income)}</strong></div><div><span>Отток</span><strong>${n(c.expense)}</strong></div><div><span>Чистый поток</span><strong>${n(c.net)}</strong></div></div><p class="section-note">${c.count} операций · переводы ${n(c.transfers)} ${esc(c.currency)} показаны отдельно</p></article>`).join('') : empty('Добавь операцию или загрузи выгрузку. Валюты не суммируются без курса.'))
    + `<details class="time-detail"><summary>Операции · ${finance.transactions.length}</summary>${table(['Дата', 'Тип', 'Сумма', 'Валюта', 'Категория', 'Описание', 'Источник', ''], finance.transactions.map(t => [esc(t.date), {income:'Приток',expense:'Отток',transfer:'Перевод'}[t.type], n(t.amountMinor / 100), esc(t.currency), esc(t.category || 'No Data'), esc(t.description || 'No Data'), esc(t.source), `<button class="text-button" data-w-action="transaction-edit" data-id="${t.id}">Исправить</button>`]))}</details>`;
}
function dataTables() {
  return {
    systems: { title: 'Системы', headers: ['Система', 'Характеристика', 'Роль', 'База', 'Цель / предел', 'Факт', 'Единица', 'Дата'], rows: workspace.systems.flatMap(s => s.characteristics.map(c => [s.name, c.name, c.kind === 'limit' ? 'Ограничитель' : 'Приоритет', c.baseline, c.target, c.current, c.unit, c.measurement?.date])) },
    goals: { title: 'Цели', headers: ['Цель', 'Статус', 'Факт', 'Цель', 'Единица', 'Срок'], rows: workspace.goals.map(g => [g.title, g.status, g.current, g.target, g.unit, g.dueDate]) },
    cases: { title: 'Кейсы', headers: ['Кейс', 'Состояние', 'Контекст', 'Следующий ход', 'Проверить', 'Результат'], rows: workspace.cases.map(c => [c.title, caseStatus[c.status], c.context, c.nextStep, c.nextReview, c.resolution]) },
    measurements: { title: 'Замеры', headers: ['Дата', 'Объект', 'Значение', 'Подтверждение', 'Работа'], rows: workspace.measurements.map(m => [m.date, workspace.systems.flatMap(s => s.characteristics).find(c => c.id === m.targetId)?.name ?? workspace.goals.find(g => g.id === m.targetId)?.title, m.value, m.evidence, workTitle(m.workRef)]) },
    reviews: { title: 'Диагностики', headers: ['Дата', 'Кейс', 'Факты', 'Неизвестно', 'Следующий ход', 'Проверить'], rows: workspace.reviews.map(r => [r.date, workspace.cases.find(c => c.id === r.caseId)?.title, r.facts, r.unknowns, r.nextStep, r.nextReview]) },
    money: { title: 'Деньги (вся история)', headers: ['Дата', 'Тип', 'Сумма', 'Валюта', 'Категория', 'Описание', 'Источник', 'ID источника'], rows: workspace.transactions.map(t => [t.date, t.type, t.amountMinor/100, t.currency, t.category, t.description, t.source, t.externalId]) }
  };
}
function renderTables() {
  const tables = dataTables(), data = tables[activeTable];
  $('workspace-tables').innerHTML = heading('Результаты, ситуации и деньги', 'Источник: data/workspace.json · вся история', button('Скачать CSV', 'export')) + `<div class="workspace-table-tabs">${Object.entries(tables).map(([key,t]) => `<button type="button" class="button secondary" data-w-action="table" data-id="${key}" aria-pressed="${key === activeTable}">${t.title}</button>`).join('')}</div>` + table(data.headers, data.rows.map(row => row.map(v => esc(v === null || v === undefined || v === '' ? 'No Data' : v))));
}
function renderAll() {
  if (!workspace) return;
  renderSystems(); renderGoals(); renderCases(); renderTables(); renderTime(); renderFinance(); renderImpacts();
  const selection = $('entry-work-ref').value;
  $('entry-work-ref').innerHTML = '<option value="">Без связи</option>' + workspace.entities.map(e => `<option value="${esc(e.ref)}">${esc(types[e.type] + ' · ' + e.title)}</option>`).join('');
  $('entry-work-ref').value = selection;
}
async function load() {
  const id = ++loadId;
  try {
    const [w, a] = await Promise.all([api('/api/workspace'), api('/api/overview?period=' + period)]);
    if (id !== loadId) return;
    workspace = w; if (a.activity.period === period) activity = a.activity;
    $('workspace-error').hidden = true;
    renderAll(); await loadFinance();
  } catch (error) { $('workspace-error').textContent = error.message; $('workspace-error').hidden = false; }
}
async function loadFinance() {
  const id = ++financeId;
  try { const result = await api('/api/finance?period=' + period); if (id === financeId) { finance = result; renderFinance(); } }
  catch (error) { $('finance-overview').innerHTML = empty(esc(error.message)); }
}
const field = (id, label, value = '', type = 'text', required = false) => `<label class="field" for="${id}">${label}<input id="${id}" type="${type}" value="${esc(value ?? '')}" ${required ? 'required' : ''} ${type === 'number' ? 'step="any"' : ''}></label>`;
const area = (id, label, value = '') => `<label class="field" for="${id}">${label}<textarea id="${id}" rows="2">${esc(value)}</textarea></label>`;
const select = (id, label, options, value = '') => `<label class="field" for="${id}">${label}<select id="${id}">${options.map(([key,title]) => `<option value="${esc(key)}" ${key === value ? 'selected' : ''}>${esc(title)}</option>`).join('')}</select></label>`;
const refField = (value = '') => select('w-ref', 'Связанная работа', [['','Без связи'], ...workspace.entities.map(e => [e.ref, `${types[e.type]} · ${e.title}`])], value ?? '');
const value = id => $(id).value;
const numeric = id => value(id) === '' ? null : Number(value(id));
function open(title, fields, action, submit = 'Сохранить') {
  $('workspace-dialog-title').textContent = title; $('workspace-fields').innerHTML = fields;
  $('workspace-form-error').hidden = true; $('workspace-submit').textContent = submit;
  submitAction = action; $('workspace-dialog').showModal();
}
async function mutate(action, input) { workspace = await api('/api/workspace', { action, input }); renderAll(); }
function systemForm(id) {
  const s = workspace.systems.find(x => x.id === id) ?? { name: '', description: '', characteristics: Array.from({length:4},(_,i) => ({ kind: i < 3 ? 'priority' : 'limit', direction: 'up' })) };
  open(id ? 'Настроить систему' : 'Новая система', field('w-name','Система',s.name,'text',true) + area('w-description','Что создаём, меняем или поддерживаем',s.description) + '<p class="field-help">Можно начать с пустых характеристик. База — исходное значение, факт записывается отдельным замером. У ограничителя верхний предел.</p>' + s.characteristics.map((c,i) => `<fieldset class="characteristic-fields"><legend>${i < 3 ? `Приоритет ${i+1}` : 'Ограничитель'}</legend>${field(`w-c-name-${i}`,'Название',c.name)}<div class="field-pair">${field(`w-c-unit-${i}`,'Единица',c.unit)}${select(`w-c-direction-${i}`,i < 3 ? 'Направление' : 'Правило', i < 3 ? [['up','Увеличить'],['down','Уменьшить']] : [['down','Не выше предела']],c.direction)}</div><div class="field-pair">${field(`w-c-base-${i}`,'База',c.baseline,'number')}${field(`w-c-target-${i}`,i < 3 ? 'Целевое значение' : 'Верхний предел',c.target,'number')}</div></fieldset>`).join(''), () => mutate('saveSystem', { id: id || undefined, name: value('w-name'), description: value('w-description'), characteristics: s.characteristics.map((c,i) => ({id:c.id, name:value(`w-c-name-${i}`), unit:value(`w-c-unit-${i}`), direction:value(`w-c-direction-${i}`), baseline:numeric(`w-c-base-${i}`), target:numeric(`w-c-target-${i}`)})) }));
}
function measurementForm(kind, id) {
  const item = kind === 'characteristic' ? workspace.systems.flatMap(s => s.characteristics).find(c => c.id === id) : workspace.goals.find(g => g.id === id);
  open(`Замер · ${item.name || item.title || 'Характеристика'}`, `<p class="field-help">Наблюдаемое значение системы. Связь с работой фиксирует контекст; сама по себе она не доказывает причинность.</p><div class="field-pair">${field('w-date','Дата',workspace.today,'date',true)}${field('w-value',`Факт, ${esc(item.unit || 'единица не задана')}`,'','number',true)}</div>${area('w-evidence','Подтверждение: наблюдение, расчёт или ссылка')}${refField()}`, () => mutate('measure', { kind, targetId:id, date:value('w-date'), value:numeric('w-value'), evidence:value('w-evidence'), workRef:value('w-ref') || null }));
}
function goalForm(id) {
  const g = workspace.goals.find(x => x.id === id) ?? {direction:'up',status:'active'};
  open(id ? 'Настроить цель' : 'Новая цель', field('w-title','Цель',g.title,'text',true) + select('w-characteristic','Источник факта', [['','Самостоятельные замеры цели'],...workspace.systems.flatMap(s=>s.characteristics.filter(c=>c.name).map(c=>[c.id,`${s.name} · ${c.name}`]))],g.characteristicId || '') + '<p class="field-help">При связи факт и единица берутся из замеров характеристики. У цели собственные база, ориентир и срок.</p>' + `<div class="field-pair">${field('w-unit','Единица для самостоятельной цели',g.unit)}${select('w-direction','Направление',[['up','Увеличить'],['down','Уменьшить']],g.direction)}</div><div class="field-pair">${field('w-base','База',g.baseline,'number')}${field('w-target','Целевое значение',g.target,'number')}</div><div class="field-pair">${field('w-due','Срок',g.dueDate,'date')}${select('w-status','Статус',[['active','Активна'],['paused','Пауза'],['archived','Архив']],g.status)}</div>` + refField(g.workRef), () => mutate('saveGoal',{id:id || undefined,title:value('w-title'),characteristicId:value('w-characteristic') || null,unit:value('w-unit'),direction:value('w-direction'),baseline:numeric('w-base'),target:numeric('w-target'),dueDate:value('w-due') || null,status:value('w-status'),workRef:value('w-ref') || null}));
}
function caseForm(id) {
  const c=workspace.cases.find(x=>x.id===id) ?? {status:'new'};
  open(id ? 'Настроить кейс' : 'Новый кейс',field('w-title','Кейс / ситуация',c.title,'text',true) + select('w-project','Проект',[['','Без проекта'],...workspace.entities.filter(e=>e.type==='project').map(e=>[e.ref.slice(8),e.title])],c.projectId || '') + select('w-status','Состояние',Object.entries(caseStatus),c.status) + area('w-context','Что сейчас известно о ситуации',c.context) + area('w-step','Следующий ход или что наблюдать',c.nextStep) + field('w-review-date','Когда вернуться',c.nextReview,'date') + area('w-resolution','Результат и основание закрытия',c.resolution),()=>mutate('saveCase',{id:id || undefined,title:value('w-title'),projectId:value('w-project') || null,status:value('w-status'),context:value('w-context'),nextStep:value('w-step'),nextReview:value('w-review-date') || null,resolution:value('w-resolution')}));
}
function reviewForm(id) {
  const c=workspace.cases.find(x=>x.id===id);
  open('Короткая диагностика · ' + c.title,field('w-date','Дата диагностики',workspace.today,'date',true) + area('w-facts','Что наблюдаю / что изменилось') + area('w-unknowns','Что ещё неизвестно / какая проверка нужна') + area('w-step','Следующий ход или осознанное наблюдение',c.nextStep) + field('w-next','Дата следующей проверки',c.nextReview || workspace.today,'date',true),()=>mutate('reviewCase',{caseId:id,date:value('w-date'),facts:value('w-facts'),unknowns:value('w-unknowns'),nextStep:value('w-step'),nextReview:value('w-next')}));
}
function linkForm(ref) {
  const link=workspace.links.find(l=>l.ownerRef===ref);
  const options=[['','Нет собственной связи / использовать проект'],...workspace.systems.map(s=>[s.id,s.name])];
  open('Влияние · ' + workTitle(ref),select('w-system','Изменяемая система',options,link?.systemId || '') + '<div id="w-impact-notes"></div>',()=>{
    const system=workspace.systems.find(s=>s.id===value('w-system'));
    return mutate('saveLink',{ownerRef:ref,systemId:system?.id || null,notes:system ? Object.fromEntries(system.characteristics.map(c=>[c.id,value('w-note-'+c.id)])) : {}});
  });
  function update() { const system=workspace.systems.find(s=>s.id===value('w-system')); $('w-impact-notes').innerHTML=system ? '<p class="field-help">Для каждого приоритета опиши ожидаемый вклад этой работы. Для ограничителя — как удержишь предел. Фактические значения берутся из замеров системы.</p>'+system.characteristics.map(c=>area('w-note-'+c.id,esc(c.name || (c.kind==='limit'?'Ограничитель':'Приоритет')),link?.systemId===system.id ? link.notes[c.id] : '')).join('') : '<p class="field-help">Если у задачи, кейса или альфы есть проект, будет использована его связь. Для самостоятельного объекта появится No Data.</p>'; }
  $('w-system').addEventListener('change',update); update();
}
function classifyForm(id) {
  const e=activity.time.entries.find(x=>x.id===id);
  const options=[...activity.metrics.filter(m=>m.unit==='hours').map(m=>[m.id,m.title]),['outside','Вне нормативов'],['unclassified','Не разобрано']];
  open('Разобрать время · ' + (e.title || e.date),select('w-metric','Норматив / назначение',options,e.metricId || e.allocation)+field('w-type','Характер работы',e.workType==='Не разобрано'?'':e.workType)+refField(e.workRef),async()=>{
    const selected=value('w-metric'),outside=['outside','unclassified'].includes(selected);
    await api('/api/entries/'+encodeURIComponent(id),{metricId:outside?null:selected,allocation:outside?selected:'assigned',workType:value('w-type'),workRef:value('w-ref')||null},'PATCH');
    window.dispatchEvent(new Event('rhythm:entry-classified')); await load();
  }); $('w-type').setAttribute('list','work-types');
}
function transactionForm(id = '') {
  const t=workspace.transactions.find(t=>t.id===id) ?? {date:workspace.today,type:'expense'};
  open(id ? 'Исправить операцию' : 'Денежная операция',`<div class="field-pair">${field('w-date','Дата',t.date,'date',true)}${select('w-type','Тип',[['expense','Расход'],['income','Поступление'],['transfer','Перевод между своими счетами']],t.type)}</div><div class="field-pair">${field('w-amount','Сумма (положительная)',t.amountMinor === undefined ? '' : t.amountMinor/100,'number',true)}${field('w-currency','Валюта · три буквы',t.currency,'text',true)}</div>${field('w-category','Категория',t.category)}${field('w-description','Описание',t.description)}${refField(t.workRef)}` + (id ? '<p class="field-help">Предыдущее значение сохранится в истории исправлений.</p>' : ''),async()=>{
    await api('/api/finance/transactions'+(id ? '/'+encodeURIComponent(id) : ''),{date:value('w-date'),type:value('w-type'),amount:numeric('w-amount'),currency:value('w-currency'),category:value('w-category'),description:value('w-description'),workRef:value('w-ref')||null},id ? 'PATCH' : 'POST'); await load();
  });
}

function importForm() {
  financeImport=null;
  open('Импорт финансовой выгрузки', '<p class="field-help">Первое подключение: CSV в UTF-8 с колонками <code>externalId,date,amount,currency,type,category,description</code>. Дата YYYY-MM-DD, положительная сумма, тип income / expense / transfer. externalId — постоянный ID операции в приложении. Для другого формата нужен образец выгрузки.</p>' + field('w-source','Источник · одно и то же имя при повторном импорте','','text',true) + '<label class="field" for="w-file">CSV-файл<input id="w-file" type="file" accept=".csv,text/csv" required></label><button type="button" class="button secondary" id="w-preview">Проверить файл</button><div id="w-import-preview"></div>',async()=>{
    if (!financeImport) throw new Error('Сначала проверь файл.');
    const result=await api('/api/finance/import',{...financeImport,commit:true}); await load();
    $('toast').textContent=`Загружено ${result.valid}; повторов пропущено ${result.duplicates}`; $('toast').hidden=false; setTimeout(()=>$('toast').hidden=true,5000);
  },'Импортировать проверенные строки');
  $('workspace-submit').disabled=true;
  const invalidate=()=>{financeImport=null; $('workspace-submit').disabled=true; $('w-import-preview').textContent='Файл ещё не проверен.';};
  $('w-file').addEventListener('change',invalidate); $('w-source').addEventListener('input',invalidate);
  $('w-preview').addEventListener('click',async()=>{
    $('workspace-form-error').hidden=true; $('w-preview').disabled=true; financeImport=null; $('workspace-submit').disabled=true;
    try {
      const file=$('w-file').files[0]; if (!file) throw new Error('Выбери CSV.'); if (file.size>2*1024*1024) throw new Error('Для первого импорта — файл до 2 МБ.');
      const candidate={csv:await file.text(),source:value('w-source')};
      const result=await api('/api/finance/import',{...candidate,commit:false});
      $('w-import-preview').innerHTML=`<p>Новых: ${result.valid} · повторов: ${result.duplicates} · ошибок: ${result.errors.length}</p>${result.errors.map(e=>`<p class="form-error">Строка ${e.row}: ${esc(e.error)}</p>`).join('')}${table(['Дата','Тип','Сумма','Валюта','Описание'],result.preview.map(t=>[esc(t.date),esc(t.type),n(t.amountMinor/100),esc(t.currency),esc(t.description)]))}`;
      if (!result.errors.length) {financeImport=candidate; $('workspace-submit').disabled=false;}
    } catch(error) {$('workspace-form-error').textContent=error.message; $('workspace-form-error').hidden=false;} finally {$('w-preview').disabled=false;}
  });
}
function exportTable() {
  const data=dataTables()[activeTable];
  const cell=v=>'"'+String(v??'').replace(/^[=+@-]/,"'$&").replaceAll('"','""')+'"';
  const csv='\uFEFF'+[data.headers,...data.rows].map(row=>row.map(cell).join(',')).join('\r\n');
  const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'})),link=document.createElement('a');
  link.href=url; link.download=`indicators-work-${activeTable}.csv`; link.click(); setTimeout(()=>URL.revokeObjectURL(url),1000);
}
document.addEventListener('click',event=>{
  const b=event.target.closest('[data-w-action]'); if (!b || !workspace) return;
  const id=b.dataset.id;
  const actions={system:()=>systemForm(id),goal:()=>goalForm(id),case:()=>caseForm(id),review:()=>reviewForm(id),link:()=>linkForm(id),'measure-characteristic':()=>measurementForm('characteristic',id),'measure-goal':()=>measurementForm('goal',id),classify:()=>classifyForm(id),transaction:()=>transactionForm(),'transaction-edit':()=>transactionForm(id),import:importForm,table:()=>{activeTable=id;renderTables();},export:exportTable};
  $('workspace-submit').disabled=false; actions[b.dataset.wAction]?.();
});
$('workspace-close').addEventListener('click',()=>$('workspace-dialog').close());
$('workspace-cancel').addEventListener('click',()=>$('workspace-dialog').close());
$('workspace-form').addEventListener('submit',async event=>{
  event.preventDefault(); $('workspace-submit').disabled=true; $('workspace-form-error').hidden=true;
  try {await submitAction(); $('workspace-dialog').close();}
  catch(error){$('workspace-form-error').textContent=error.message; $('workspace-form-error').hidden=false;}
  finally{$('workspace-submit').disabled=false;}
});
window.addEventListener('rhythm:overview-loaded',event=>{activity=event.detail; period=activity.period; renderTime(); void loadFinance();});
window.addEventListener('rhythm:portfolio-rendered',renderImpacts);
window.addEventListener('rhythm:work-link-changed',renderImpacts);
window.addEventListener('rhythm:portfolio-saved',()=>void load());
$('data-refresh').addEventListener('click',()=>void load());
void load();
