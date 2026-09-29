const $ = id => document.getElementById(id);
const nf = new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 2 });
let state = null;
let selectedWeek = null;
let requestId = 0;
let deleteId = null;
let toastTimer;
const icons = {
  guides: '<path d="M4 4h6a3 3 0 0 1 3 3v13a3 3 0 0 0-3-3H4z"/><path d="M13 7a3 3 0 0 1 3-3h5v13h-5a3 3 0 0 0-3 3"/>',
  reading: '<path d="M5 3h14v18H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Z"/><path d="M7 3v14M3 17h16M11 7h5M11 10h5"/>',
  house_sale: '<path d="m3 11 9-8 9 8M5 9v12h14V9M10 21v-7h4v7"/>',
  business: '<rect x="3" y="7" width="18" height="14" rx="2"/><path d="M8 7V3h8v4M3 12a21 21 0 0 0 18 0M10 13h4"/>',
  work_support: '<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8M12 17v4m-5-8 3-3 3 2 4-4"/>',
  household: '<path d="M4 21h16M6 21V9l6-5 6 5v12M9 14h6M12 11v7"/>',
  other: '<circle cx="6" cy="6" r="2"/><circle cx="18" cy="6" r="2"/><circle cx="6" cy="18" r="2"/><circle cx="18" cy="18" r="2"/>',
  alphas: '<rect x="5" y="4" width="15" height="17" rx="2"/><path d="M9 4V2h7v2M9 12l3 3 5-6"/>'
};
const editIcon = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 4 5 5M4 20l5-1L21 7a2 2 0 0 0-4-4L5 15z"/></svg>';
const esc = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const format = value => nf.format(value);
const date = value => new Date(`${value}T12:00:00Z`);
const dateLabel = value => date(value).toLocaleDateString('ru-RU', { day: 'numeric', month: 'long', timeZone: 'UTC' });
const weekLabel = data => `${dateLabel(data.week)} — ${dateLabel(data.end)} ${date(data.end).getUTCFullYear()}`;
const shift = (value, days) => { const d = date(value); d.setUTCDate(d.getUTCDate() + days); return d.toISOString().slice(0, 10); };
const unit = metric => metric.unit === 'hours' ? 'ч' : 'шт.';
const clamp = value => Math.min(100, Math.max(0, value ?? 0));
const observed = metric => metric.recordCount > 0;
const actualLabel = metric => observed(metric) ? format(metric.actual) : 'No Data';
const targetLabel = metric => metric.target === null ? 'No Data' : format(metric.target);

async function api(url, options = {}) {
  const response = await fetch(url, { ...options, headers: { 'Content-Type': 'application/json', ...options.headers } });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error ?? 'Не удалось выполнить запрос.');
  return result;
}

function toast(message) {
  clearTimeout(toastTimer);
  $('toast').textContent = message;
  $('toast').hidden = false;
  toastTimer = setTimeout(() => { $('toast').hidden = true; }, 3500);
}

function track(metric, extraClass = '') {
  const hasData = observed(metric);
  const aria = metric.target === null ? 'Норматив не задан' : hasData ? `${metric.title}: ${format(metric.actual)} из ${format(metric.target)} ${unit(metric)}` : `${metric.title}: No Data, записей пока нет`;
  return `<div class="progress-track ${extraClass} ${hasData ? '' : 'no-data'}" role="progressbar" aria-label="${esc(aria)}" aria-valuemin="0" aria-valuemax="100" ${hasData ? `aria-valuenow="${clamp(metric.percent)}"` : ''} aria-valuetext="${esc(aria)}"><div class="progress-fill" style="width:${hasData ? clamp(metric.percent) : 0}%"></div></div>`;
}

function card(metric) {
  const unset = metric.target === null;
  const finished = !unset && metric.actual >= metric.target;
  const bottom = unset ? 'Недельный план не задан' : !observed(metric) ? 'Данных о выполнении пока нет' : finished ? `Норматив выполнен${metric.actual > metric.target ? ` · сверх плана ${format(metric.actual - metric.target)} ${unit(metric)}` : ''}` : `Осталось ${format(metric.remaining)} ${unit(metric)}`;
  return `<article class="goal-card ${unset ? 'unset' : ''} ${observed(metric) ? '' : 'without-data'}" data-color="${metric.color}"><div class="card-heading"><div class="card-title"><span class="card-icon"><svg viewBox="0 0 24 24" aria-hidden="true">${icons[metric.id]}</svg></span><h3>${metric.title}</h3></div><button class="edit-card" data-edit="${metric.id}" aria-label="Изменить норматив: ${metric.title}">${editIcon}</button></div><p class="card-description">${metric.description}</p><div class="card-value"><strong>${actualLabel(metric)}</strong><span class="plan-value">/ ${targetLabel(metric)} ${unit(metric)}</span>${unset ? '' : `<span class="percent">${observed(metric) ? `${metric.percent}%` : 'No Data'}</span>`}</div>${track(metric)}<div class="card-bottom"><span>${bottom}</span>${unset ? `<button class="text-button" data-edit="${metric.id}">Задать</button>` : `<span>${metric.recordCount ? `${metric.recordCount} зап.` : 'No Data'}</span>`}</div></article>`;
}

function guidesCard(guides, mentor) {
  const combined = guides.actual + mentor.actual;
  const hasData = observed(guides) || observed(mentor);
  const total = (guides.target ?? 0) + (mentor.target ?? 0);
  const hasTargets = guides.target !== null || mentor.target !== null;
  const weighted = total ? ((guides.target === null ? 0 : Math.min(guides.actual, guides.target)) + (mentor.target === null ? 0 : Math.min(mentor.actual, mentor.target))) / total * 100 : 0;
  const line = (metric, label, extra) => `<div><div class="guide-line"><span>${label}</span><strong>${actualLabel(metric)} / ${targetLabel(metric)} ч</strong></div>${track(metric, extra)}</div>`;
  return `<article class="goal-card guide-card ${hasData ? '' : 'without-data'}"><div class="card-heading"><div class="card-title"><span class="card-icon"><svg viewBox="0 0 24 24" aria-hidden="true">${icons.guides}</svg></span><h3>Руководства и проект</h3></div><button class="edit-card" data-edit="guides" aria-label="Изменить норматив руководств и наставника">${editIcon}</button></div><div class="guide-layout"><div class="guide-bars">${line(guides, 'Самостоятельная работа', '')}${line(mentor, 'Разбор с наставником', 'mentor-track')}</div><div class="guide-ring ${hasData ? '' : 'no-data'}" style="--ring-angle:${hasData ? clamp(weighted) * 3.6 : 0}deg" role="img" aria-label="${hasData ? `Выполнено ${Math.round(weighted)} процентов нормативов руководств и наставника` : 'No Data: работа пока не учтена'}"><div class="ring-inner"><strong>${hasData ? `${format(combined)}<span style="font-size:16px"> ч</span>` : 'No Data'}</strong><span>${hasTargets ? `из ${format(total)} ч` : 'нет норматива'}</span></div></div></div><div class="guide-bottom"><span>${hasTargets ? `Ориентир: ${format(total)} ч в неделю` : 'Задай нормативы для двух направлений'}</span><span>${!hasData ? 'No Data' : guides.actual >= (guides.target ?? Infinity) && mentor.actual >= (mentor.target ?? Infinity) ? 'Оба норматива выполнены' : `${Math.round(weighted)}% плана`}</span></div></article>`;
}

function render() {
  $('dashboard').setAttribute('aria-busy', 'false');
  $('week-label').textContent = weekLabel(state);
  $('week-tag').textContent = state.week === state.currentWeek ? 'Текущая неделя' : state.week < state.currentWeek ? 'Прошлая неделя' : 'Будущая неделя';
  $('hours-actual').textContent = state.metrics.some(metric => metric.unit === 'hours' && observed(metric)) ? format(state.summary.actualHours) : 'No Data';
  $('hours-target').textContent = ` / ${state.summary.targetHours ? format(state.summary.targetHours) : 'No Data'} ч`;
  $('hours-hint').textContent = state.summary.unconfigured ? 'План учитывает заданные нормативы часов' : 'По всем направлениям недели';
  $('completed').textContent = state.summary.completed;
  $('configured').textContent = ` / ${state.summary.configured}`;
  $('configured-hint').textContent = state.summary.unconfigured ? `Осталось задать: ${state.summary.unconfigured}` : 'Все нормативы заданы';
  const alpha = state.metrics.find(metric => metric.id === 'alphas');
  $('alpha-actual').textContent = actualLabel(alpha);
  $('alpha-target').textContent = ` / ${targetLabel(alpha)}`;
  $('alpha-hint').textContent = alpha.target === null ? 'Норматив — в настройках недели' : alpha.remaining === 0 ? 'Норматив выполнен' : `Осталось ${format(alpha.remaining)} шт.`;
  const guides = state.metrics.find(metric => metric.id === 'guides');
  const mentor = state.metrics.find(metric => metric.id === 'mentor');
  $('goals-grid').innerHTML = guidesCard(guides, mentor) + state.metrics.filter(metric => !['guides', 'mentor'].includes(metric.id)).map(card).join('');
  $('entry-count').textContent = state.entries.length;
  $('journal').innerHTML = state.entries.length ? `<div class="journal-list">${state.entries.map(entry => {
    const metric = state.metrics.find(item => item.id === entry.metricId);
    return `<div class="journal-row"><span class="journal-date">${date(entry.date).toLocaleDateString('ru-RU', { day: 'numeric', month: 'short', timeZone: 'UTC' })}</span><div><div class="journal-title">${esc(entry.title || metric.title)}</div><div class="journal-category">${metric.title} · ${entry.source === 'manual' ? 'Вручную' : esc(entry.source)}</div></div><strong class="journal-amount">${format(entry.amount)} ${unit(metric)}</strong><button class="delete-entry" data-delete="${entry.id}" aria-label="Удалить запись: ${esc(entry.title || metric.title)}">×</button></div>`;
  }).join('')}</div>` : '<div class="journal-empty"><div><strong>No Data</strong><p>Нормативы уже готовы. Добавь первую запись — прогресс посчитается автоматически.</p></div></div>';
  $('save-label').textContent = `Недельные записи сохранены · ${new Date(state.updatedAt).toLocaleTimeString('ru-RU', { timeZone: 'Asia/Tashkent', hour: '2-digit', minute: '2-digit' })}`;
  window.dispatchEvent(new CustomEvent('rhythm:week-loaded', { detail: { week: state.week } }));
}

async function load(week = selectedWeek) {
  const currentRequest = ++requestId;
  $('dashboard').setAttribute('aria-busy', 'true');
  for (const id of ['previous-week', 'next-week', 'current-week', 'targets-button', 'entry-button', 'journal-add']) $(id).disabled = true;
  try {
    const result = await api(`/api/dashboard${week ? `?week=${encodeURIComponent(week)}` : ''}`);
    if (currentRequest !== requestId) return;
    state = result;
    selectedWeek = result.week;
    $('load-error').hidden = true;
    render();
  } catch (error) {
    if (currentRequest !== requestId) return;
    $('load-error-text').textContent = `Не удалось загрузить неделю. ${error.message}`;
    $('load-error').hidden = false;
    $('dashboard').setAttribute('aria-busy', 'false');
  } finally {
    if (currentRequest === requestId) {
      for (const id of ['previous-week', 'next-week', 'current-week', 'targets-button', 'entry-button', 'journal-add']) $(id).disabled = !state;
    }
  }
}

function openTargets(focusId = null) {
  if (!state) return;
  $('targets-week').textContent = weekLabel(state);
  $('targets-error').hidden = true;
  $('target-fields').innerHTML = state.metrics.map(metric => `<label class="target-row" for="target-${metric.id}"><span><span class="target-name">${metric.title}</span><span class="target-note">${metric.id === 'guides' ? 'Самостоятельно, без наставника' : metric.id === 'mentor' ? 'Отдельно от самостоятельной работы' : metric.id === 'reading' ? 'Отдельный норматив чтения' : 'На выбранную неделю'}</span></span><span class="target-input-wrap"><input id="target-${metric.id}" name="${metric.id}" type="number" min="${metric.unit === 'hours' ? '0.01' : '1'}" max="${metric.unit === 'hours' ? '168' : '10000'}" step="${metric.unit === 'hours' ? '0.01' : '1'}" inputmode="${metric.unit === 'hours' ? 'decimal' : 'numeric'}" value="${metric.target ?? ''}" aria-label="Норматив: ${metric.title}"><span>${unit(metric)}/нед.</span></span></label>`).join('');
  updateTargetsTotal();
  $('targets-dialog').showModal();
  if (focusId) { const input = $(`target-${focusId}`); input.focus(); input.select(); }
}

function updateTargetsTotal() {
  if (!state) return;
  const total = state.metrics.filter(metric => metric.unit === 'hours').reduce((sum, metric) => sum + (Number($(`target-${metric.id}`).value) || 0), 0);
  $('targets-total').textContent = `План по заданным нормативам: ${format(total)} ч в неделю${total > 168 ? ' · больше 168 часов' : ''}`;
}

function entryUnit() {
  const count = $('entry-metric').value === 'alphas';
  $('entry-amount-label').textContent = count ? 'Количество альф, шт.' : 'Время, ч';
  $('entry-amount').min = count ? '1' : '0.01';
  $('entry-amount').max = count ? '10000' : '24';
  $('entry-amount').step = count ? '1' : '0.01';
  $('entry-amount').inputMode = count ? 'numeric' : 'decimal';
  $('entry-amount-help').textContent = count ? 'Укажи количество заполненных альф.' : '30 минут = 0,5 ч · 1 час 30 минут = 1,5 ч';
}

function openEntry() {
  if (!state) return;
  $('entry-form').reset();
  $('entry-error').hidden = true;
  $('entry-metric').innerHTML = state.metrics.map(metric => `<option value="${metric.id}">${metric.title}</option>`).join('');
  $('entry-date').value = state.week === state.currentWeek ? state.today : state.week;
  entryUnit();
  $('entry-dialog').showModal();
}

async function submit(form, errorId, action) {
  const button = form.querySelector('button[type="submit"]');
  button.disabled = true;
  $(errorId).hidden = true;
  try { await action(); } catch (error) { $(errorId).textContent = error.message; $(errorId).hidden = false; } finally { button.disabled = false; }
}

async function saveTargets(targets) {
  state = await api('/api/targets', { method: 'PUT', body: JSON.stringify({ week: state.week, targets }) });
  render();
  return { week: state.week, targets: Object.fromEntries(state.metrics.map(metric => [metric.id, metric.target])), summary: state.summary };
}

$('targets-button').addEventListener('click', () => openTargets());
$('entry-button').addEventListener('click', openEntry);
$('journal-add').addEventListener('click', openEntry);
$('previous-week').addEventListener('click', () => load(shift(state.week, -7)));
$('next-week').addEventListener('click', () => load(shift(state.week, 7)));
$('current-week').addEventListener('click', () => load(state.currentWeek));
$('retry-button').addEventListener('click', () => load());
window.addEventListener('rhythm:portfolio-saved', () => { void load(); });
$('entry-metric').addEventListener('change', entryUnit);
$('target-fields').addEventListener('input', updateTargetsTotal);
$('goals-grid').addEventListener('click', event => { const edit = event.target.closest('[data-edit]'); if (edit) openTargets(edit.dataset.edit); });
document.querySelectorAll('.close-modal').forEach(button => button.addEventListener('click', () => button.closest('dialog').close()));
document.querySelectorAll('dialog').forEach(dialog => dialog.addEventListener('click', event => { if (event.target !== dialog) return; const rect = dialog.getBoundingClientRect(); if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close(); }));

$('targets-form').addEventListener('submit', event => {
  event.preventDefault();
  void submit(event.currentTarget, 'targets-error', async () => {
    const targets = Object.fromEntries(state.metrics.map(metric => { const value = $(`target-${metric.id}`).value; return [metric.id, value === '' ? null : Number(value)]; }));
    await saveTargets(targets);
    $('targets-dialog').close();
    toast('Нормативы сохранены');
  });
});

$('entry-form').addEventListener('submit', event => {
  event.preventDefault();
  void submit(event.currentTarget, 'entry-error', async () => {
    const input = { metricId: $('entry-metric').value, date: $('entry-date').value, amount: Number($('entry-amount').value), title: $('entry-title').value };
    await api('/api/entries', { method: 'POST', body: JSON.stringify(input) });
    $('entry-dialog').close();
    await load(input.date);
    toast('Запись добавлена. Прогресс пересчитан');
  });
});

$('journal').addEventListener('click', event => {
  const button = event.target.closest('[data-delete]');
  if (!button) return;
  deleteId = button.dataset.delete;
  const entry = state.entries.find(item => item.id === deleteId);
  const metric = state.metrics.find(item => item.id === entry.metricId);
  $('delete-description').textContent = `${entry.title || metric.title} · ${format(entry.amount)} ${unit(metric)} · ${dateLabel(entry.date)}. Прогресс недели будет пересчитан.`;
  $('delete-error').hidden = true;
  $('delete-dialog').showModal();
});

$('delete-form').addEventListener('submit', event => {
  event.preventDefault();
  void submit(event.currentTarget, 'delete-error', async () => {
    await api(`/api/entries/${deleteId}`, { method: 'DELETE' });
    $('delete-dialog').close();
    await load();
    toast('Запись удалена');
  });
});

void load();

if (document.modelContext?.registerTool) {
  const lifecycle = new AbortController();
  const tools = [
    {
      name: 'read_weekly_dashboard', title: 'Посмотреть нормативы и прогресс недели',
      description: 'Прочитать нормативы и прогресс выбранной в дашборде недели. Не меняет данные.',
      inputSchema: { type: 'object', properties: {}, additionalProperties: false },
      annotations: { readOnlyHint: true, untrustedContentHint: true },
      execute() {
        if (!state) throw new Error('Неделя ещё не загружена.');
        return { week: state.week, summary: state.summary, metrics: state.metrics.map(({ id, title, unit, target, actual, percent }) => ({ id, title, unit, target, actual, percent })) };
      }
    },
    {
      name: 'save_weekly_targets', title: 'Сохранить нормативы выбранной недели',
      description: 'Изменить и сохранить нормативы выбранной недели. Идентификаторы направлений доступны в read_weekly_dashboard. null снимает норматив; часы — положительное число до 168, альфы — целое число до 10000.',
      inputSchema: { type: 'object', properties: { targets: { type: 'object', properties: Object.fromEntries(Object.keys(icons).concat('mentor').map(id => [id, { type: ['number', 'null'] }])), additionalProperties: false, minProperties: 1 } }, required: ['targets'], additionalProperties: false },
      annotations: { readOnlyHint: false, untrustedContentHint: false },
      async execute(input) {
        if (!state) throw new Error('Неделя ещё не загружена.');
        if (!input || typeof input !== 'object' || !input.targets) throw new Error('Укажи нормативы.');
        const result = await saveTargets(input.targets);
        toast('Нормативы сохранены');
        return result;
      }
    }
  ];
  for (const tool of tools) {
    try { void Promise.resolve(document.modelContext.registerTool(tool, { signal: lifecycle.signal })).catch(error => console.warn('WebMCP:', error.message)); }
    catch (error) { console.warn('WebMCP:', error.message); }
  }
  window.addEventListener('pagehide', () => lifecycle.abort(), { once: true });
}
