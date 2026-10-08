const $ = id => document.getElementById(id);
const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const number = new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 2 });
const dateLabel = date => new Date(`${date}T12:00:00Z`).toLocaleDateString('ru-RU', { day: 'numeric', month: 'long', timeZone: 'UTC' });
const stateLabel = { planned: 'Выбрано', in_progress: 'В работе', blocked: 'Есть препятствие', ready: 'Готово' };
const typeLabel = { project: 'Проект', alpha: 'Альфа', task: 'Задача', case: 'Кейс', system: 'Система' };
const fields = ['today-result-text', 'today-result-state', 'today-result-progress', 'today-result-evidence', 'today-work-ref', 'today-why-important', 'today-next-step', 'today-focus-window'];
let snapshot = null, todaySnapshot = null, savedResult = null, draftDate = null, selectedDate = null;
let dirty = false, saving = false, loading = false, requestId = 0, queryPicked = false;
let entities = [], timeEntries = [];

async function get(url) {
  const response = await fetch(url);
  const result = await response.json();
  if (!response.ok) throw new Error(result.error ?? 'Не удалось прочитать данные.');
  return result;
}
function status(message, error = false) {
  $('today-result-status').textContent = message;
  $('today-result-status').classList.toggle('problem-error', error);
}
function progressValue() {
  const value = $('today-result-progress').value;
  return value === '' ? null : Number(value);
}
function evidenceField() {
  const ready = $('today-result-state').value === 'ready';
  $('today-evidence-row').hidden = !ready && !$('today-result-evidence').value;
  $('today-result-evidence').required = ready;
  $('today-result-progress').readOnly = ready;
  if (ready) $('today-result-progress').value = '100';
}
function renderProgress() {
  const progress = progressValue(), bar = $('work-progress-track');
  const known = Number.isInteger(progress) && progress >= 0 && progress <= 100;
  bar.firstElementChild.style.width = `${known ? progress : 0}%`;
  bar.classList.toggle('no-data', !known);
  bar.setAttribute('aria-valuetext', known ? `${progress}% · оценка продвижения` : 'No Data');
  if (known) bar.setAttribute('aria-valuenow', String(progress)); else bar.removeAttribute('aria-valuenow');
}
function options(selected = $('today-work-ref').value) {
  const values = [{ ref: '', title: 'Без связи' }, ...entities];
  if (selected && !values.some(item => item.ref === selected)) values.push({ ref: selected, title: `${selected} · объект недоступен` });
  $('today-work-ref').innerHTML = values.map(item => `<option value="${escapeHtml(item.ref)}">${item.type ? `${typeLabel[item.type] ?? item.type} · ` : ''}${escapeHtml(item.title)}</option>`).join('');
  $('today-work-ref').value = selected;
}
function renderWorkContext() {
  const ref = $('today-work-ref').value;
  const records = timeEntries.filter(item => item.date === draftDate && item.workRef === ref && item.metricId !== 'alphas');
  $('today-work-hours').textContent = ref && records.length ? `${number.format(records.reduce((sum, item) => sum + item.amount, 0))} ч` : 'No Data';
  $('work-impact-details').hidden = !ref;
  if (ref) $('work-impact').dataset.impactRef = ref;
  else { $('work-impact').removeAttribute('data-impact-ref'); $('work-impact').replaceChildren(); }
  $('work-open-source').hidden = !ref.startsWith('alpha:');
  if (ref.startsWith('alpha:')) $('work-open-source').href = `/alphas?alpha=${encodeURIComponent(ref.slice(6))}`;
  window.dispatchEvent(new Event('rhythm:work-link-changed'));
}
function fillResult(result) {
  savedResult = result;
  $('today-result-text').value = result?.text ?? '';
  $('today-result-state').value = result?.status ?? 'planned';
  $('today-result-progress').value = result?.progress ?? '';
  $('today-result-evidence').value = result?.evidence ?? '';
  $('today-why-important').value = result?.whyImportant ?? '';
  $('today-next-step').value = result?.nextStep ?? '';
  $('today-focus-window').value = result?.focusWindow ?? '';
  options(result?.workRef ?? '');
  evidenceField(); renderProgress(); renderWorkContext();
  status(result ? `${stateLabel[result.status]} · сохранено` : 'No Data');
}
function renderSummary() {
  if (!todaySnapshot) return;
  const result = todaySnapshot.result, problem = todaySnapshot.problem;
  const object = entities.find(item => item.ref === result?.workRef);
  const progress = result?.progress ?? null;
  $('focus-summary').innerHTML = `<div class="focus-summary-heading"><span class="eyebrow">ГЛАВНОЕ СЕГОДНЯ · ${escapeHtml(dateLabel(todaySnapshot.date))}</span><button type="button" class="text-button" data-open-work>Открыть работу →</button></div><div class="focus-summary-content"><div><h2>${escapeHtml(result?.text || 'No Data')}</h2><p>Проблема: ${escapeHtml(problem?.text || 'No Data')}</p>${object ? `<p>${escapeHtml(typeLabel[object.type] ?? '')} · ${escapeHtml(object.title)}</p>` : ''}${result?.nextStep ? `<p>Следующий ход: ${escapeHtml(result.nextStep)}</p>` : ''}${result?.focusWindow ? `<p>Окно фокуса: ${escapeHtml(result.focusWindow)}</p>` : ''}</div><div class="focus-summary-percent"><strong>${progress === null ? 'No Data' : `${progress}%`}</strong><span>${result ? stateLabel[result.status] : 'Работа ещё не выбрана'}</span></div></div><div class="work-progress-track${progress === null ? ' no-data' : ''}" role="progressbar" aria-label="Главная работа сегодня" aria-valuemin="0" aria-valuemax="100" ${progress === null ? 'aria-valuetext="No Data"' : `aria-valuenow="${progress}" aria-valuetext="${progress}% · оценка продвижения"`}><span style="width:${progress ?? 0}%"></span></div>`;
}
function render() {
  const { date, week, end, dailyTime, weeklyTime, norms, daysRemaining } = snapshot;
  $('today-date').textContent = dateLabel(date);
  $('today-hours').textContent = dailyTime.total === null ? 'No Data' : `${number.format(dailyTime.total)} ч`;
  $('today-hours-detail').textContent = dailyTime.records ? dailyTime.byAllocation.map(item => `${item.title}: ${number.format(item.hours)} ч`).join(' · ') : 'Записей времени за этот день пока нет';
  $('today-completed').textContent = `${snapshot.completed} / ${norms.length}`;
  $('today-completed-detail').textContent = norms.length ? 'норм подтверждено учётными записями' : 'Недельные нормативы ещё не заданы';
  $('today-days').textContent = String(daysRemaining);
  $('today-week-label').textContent = `Нормы недели · ${dateLabel(week)} — ${dateLabel(end)}`;
  $('today-norms').innerHTML = norms.length ? norms.map(metric => {
    const unit = metric.unit === 'hours' ? 'ч' : 'шт.';
    const actual = metric.actual === null ? 'No Data' : number.format(metric.actual);
    const remainder = metric.complete ? 'Норма выполнена' : `Осталось по учёту ${number.format(metric.remaining)} ${unit}`;
    const pace = metric.complete ? 'Можно выбрать другую работу' : `В среднем ${number.format(metric.dailyPace)} ${unit}/день до воскресенья`;
    return `<article class="today-norm${metric.complete ? ' today-norm-complete' : ''}"><div class="today-norm-top"><h3>${escapeHtml(metric.title)}</h3><strong>${actual}<small> / ${number.format(metric.target)} ${unit}</small></strong></div><div class="today-norm-track" role="progressbar" aria-label="Норма недели: ${escapeHtml(metric.title)}" aria-valuemin="0" aria-valuemax="100" ${metric.percent === null ? 'aria-valuetext="No Data"' : `aria-valuenow="${Math.min(metric.percent, 100)}" aria-valuetext="${metric.percent}%"`}><span style="width:${metric.percent === null ? 0 : Math.min(metric.percent, 100)}%"></span></div><p>${remainder}</p><div class="today-norm-bottom"><span>${pace}</span><button type="button" class="text-button" data-today-metric="${metric.id}">Учесть →</button></div></article>`;
  }).join('') : '<p class="today-note">No Data · задай недельные нормативы в настройках.</p>';
  $('today-coverage').textContent = weeklyTime.records ? 'Остатки и темп рассчитаны по учтённым записям до выбранного дня. Дни включают выбранный день; доступное время и расписание не заданы.' : 'No Data · до выбранного дня в этой неделе нет записей времени. Сначала внеси уже потраченное время.';
  if (!dirty && !saving) {
    draftDate = date;
    $('work-date').value = date; $('work-date').max = todaySnapshot.date;
    fillResult(snapshot.result);
    window.dispatchEvent(new CustomEvent('rhythm:work-date-selected', { detail: { date } }));
  } else { options(); renderWorkContext(); }
  $('today-result-label').firstChild.textContent = `Самое важное · ${dateLabel(draftDate ?? date)}`;
  $('today-add-time').disabled = false;
  renderSummary();
}
async function load() {
  const id = ++requestId;
  loading = true; $('today-result-save').disabled = true;
  if (!dirty) fields.forEach(id => { $(id).disabled = true; });
  try {
    const date = selectedDate ?? ((dirty || window.rhythmDailyProblem?.isDirty()) ? draftDate : null);
    const [day, current, workspace, time] = await Promise.all([get(`/api/today${date ? `?date=${date}` : ''}`), date ? get('/api/today') : null, get('/api/workspace'), get('/api/time-entries')]);
    if (id !== requestId) return;
    snapshot = day; todaySnapshot = current ?? day; entities = workspace.entities; timeEntries = time.entries;
    $('today-error').hidden = true; $('today-retry').hidden = true;
    render();
  } catch (error) {
    if (id !== requestId) return;
    $('today-error').textContent = error.message; $('today-error').hidden = false; $('today-retry').hidden = false;
  } finally {
    if (id === requestId) {
      loading = false; fields.forEach(id => { $(id).disabled = saving; }); $('today-result-save').disabled = saving || !snapshot || snapshot.date !== draftDate;
      if (snapshot && !queryPicked) void initializeFocusLink();
    }
  }
}
async function selectDate(date) {
  const problem = window.rhythmDailyProblem;
  if (date === draftDate && snapshot?.date === date) return true;
  if (saving || problem?.isSaving() || loading) { $('work-date').value = draftDate ?? ''; return false; }
  if ((dirty || problem?.isDirty()) && !window.confirm('Есть несохранённые изменения главной работы или проблемы. Перейти к другому дню?')) { $('work-date').value = draftDate; return false; }
  dirty = false; selectedDate = date === todaySnapshot?.date ? null : date;
  draftDate = date;
  window.dispatchEvent(new CustomEvent('rhythm:work-date-selected', { detail: { date, discard: true } }));
  await load(); return snapshot?.date === date;
}
async function pickWork(input) {
  if (!snapshot || saving || loading || window.rhythmDailyProblem?.isSaving()) return;
  if ((dirty || window.rhythmDailyProblem?.isDirty()) && !window.confirm('Перенести объект из моделера? Несохранённые изменения главной работы или проблемы будут сброшены.')) return;
  dirty = false; selectedDate = null;
  window.dispatchEvent(new CustomEvent('rhythm:work-date-selected', { detail: { date: todaySnapshot.date, discard: true } }));
  await load();
  if (snapshot?.date !== todaySnapshot?.date || !entities.some(item => item.ref === input?.workRef)) { status('Объект недоступен. Обнови данные.', true); return; }
  if (snapshot.result?.workRef === input.workRef) { window.dispatchEvent(new Event('rhythm:show-work')); return; }
  $('today-work-ref').value = input.workRef;
  $('today-result-text').value = (input.text ?? '').slice(0, 2000);
  $('today-why-important').value = (input.whyImportant ?? '').slice(0, 1000);
  $('today-next-step').value = (input.nextStep ?? '').slice(0, 1000);
  $('today-result-state').value = 'planned'; $('today-result-progress').value = ''; $('today-result-evidence').value = '';
  dirty = true; evidenceField(); renderProgress(); renderWorkContext();
  status('Подготовлено из моделера · проверь и сохрани');
  window.dispatchEvent(new Event('rhythm:show-work'));
}
function addTime(metricId = null) {
  if (snapshot) window.dispatchEvent(new CustomEvent('rhythm:add-today-entry', { detail: { date: snapshot.date, metricId, workRef: $('today-work-ref').value, title: $('today-result-text').value } }));
}
$('today-add-time').addEventListener('click', () => addTime());
$('today-norms').addEventListener('click', event => { const button = event.target.closest('[data-today-metric]'); if (button) addTime(button.dataset.todayMetric); });
$('today-retry').addEventListener('click', () => void load());
$('work-date').addEventListener('change', () => void selectDate($('work-date').value));
$('work-current-day').addEventListener('click', () => { if (todaySnapshot) void selectDate(todaySnapshot.date); });
$('focus-summary').addEventListener('click', async event => { if (event.target.closest('[data-open-work]') && await selectDate(todaySnapshot.date)) window.dispatchEvent(new Event('rhythm:show-work')); });
$('today-result-history').addEventListener('click', () => window.dispatchEvent(new Event('rhythm:show-daily-results')));
$('today-result-state').addEventListener('change', () => { if ($('today-result-state').value !== 'ready' && progressValue() === 100) $('today-result-progress').value = ''; });
function changed() { dirty = true; status('Не сохранено'); evidenceField(); renderProgress(); renderWorkContext(); }
$('today-result-form').addEventListener('input', changed);
$('today-result-form').addEventListener('change', changed);
$('today-result-form').addEventListener('submit', async event => {
  event.preventDefault();
  if (saving || loading || !snapshot) return;
  const input = { date: draftDate, text: $('today-result-text').value, status: $('today-result-state').value, progress: progressValue(), evidence: $('today-result-evidence').value, workRef: $('today-work-ref').value || null, whyImportant: $('today-why-important').value, nextStep: $('today-next-step').value, focusWindow: $('today-focus-window').value, expectedUpdatedAt: savedResult?.updatedAt ?? null };
  saving = true; $('today-result-save').disabled = true; fields.forEach(id => { $(id).disabled = true; }); status('Сохраняю…');
  try {
    const response = await fetch('/api/daily-results', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(input) });
    const result = await response.json();
    if (!response.ok) {
      dirty = true;
      const history = await get('/api/daily-results'); savedResult = history.entries.find(item => item.date === input.date) ?? null;
      throw new Error(result.error ?? 'Не удалось сохранить работу.');
    }
    savedResult = result; dirty = false; status(`${stateLabel[result.status]} · сохранено`);
    window.dispatchEvent(new Event('rhythm:daily-result-saved'));
  } catch (error) { dirty = true; status(error.message, true); }
  finally { saving = false; fields.forEach(id => { $(id).disabled = false; }); $('today-result-save').disabled = loading; }
  if (!dirty) await load();
});
window.addEventListener('rhythm:pick-work', event => void pickWork(event.detail));
window.addEventListener('beforeunload', event => { if (dirty || window.rhythmDailyProblem?.isDirty()) { event.preventDefault(); event.returnValue = ''; } });
for (const event of ['rhythm:week-loaded', 'rhythm:entry-classified', 'rhythm:daily-problem-saved', 'rhythm:portfolio-saved', 'rhythm:work-opened', 'focus']) window.addEventListener(event, () => { if (!saving) void load(); });
async function initializeFocusLink() {
  const id = new URLSearchParams(location.search).get('focusAlpha');
  if (!id || queryPicked || !snapshot) return;
  queryPicked = true;
  try {
    const portfolio = await get('/api/portfolio'), alpha = portfolio.alphas.find(item => item.id === id);
    if (loading) { queryPicked = false; return; }
    if (alpha) await pickWork({ workRef: `alpha:${id}`, text: alpha.nextStep || `Продвинуть ${alpha.uniqueName || alpha.typeName}`, whyImportant: alpha.whyImportant, nextStep: alpha.nextStep });
    else status('Объект из ссылки не найден.', true);
    const url = new URL(location.href); url.searchParams.delete('focusAlpha');
    history.replaceState(null, '', `${url.pathname}${url.search}${url.hash}`);
  } catch (error) { status(error.message, true); }
}
void load();
