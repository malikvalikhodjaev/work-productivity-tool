const $ = id => document.getElementById(id);
const escapeHtml = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const number = new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 2 });
const dateLabel = date => new Date(`${date}T12:00:00Z`).toLocaleDateString('ru-RU', { day: 'numeric', month: 'long', timeZone: 'UTC' });
let snapshot = null, savedResult = null, draftDate = null, dirty = false, saving = false, loading = false, requestId = 0;

function status(message, error = false) {
  $('today-result-status').textContent = message;
  $('today-result-status').classList.toggle('problem-error', error);
}
function evidenceField() {
  $('today-evidence-row').hidden = !$('today-result-ready').checked && !$('today-result-evidence').value;
  $('today-result-evidence').required = $('today-result-ready').checked;
}
function render() {
  const { date, week, end, dailyTime, weeklyTime, norms, daysRemaining } = snapshot;
  $('today-date').textContent = dateLabel(date);
  $('today-hours').textContent = dailyTime.total === null ? 'No Data' : `${number.format(dailyTime.total)} ч`;
  $('today-hours-detail').textContent = dailyTime.records ? dailyTime.byAllocation.map(item => `${item.title}: ${number.format(item.hours)} ч`).join(' · ') : 'Записей времени за сегодня пока нет';
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
  $('today-coverage').textContent = weeklyTime.records ? 'Остатки и темп рассчитаны по учтённым записям до сегодня. Дни включают сегодня; доступное время и расписание не заданы.' : 'No Data · учёт времени за эту неделю пока пустой. Остатки рассчитаны без записей факта; сначала внеси уже потраченное время.';
  if (!dirty && !saving) {
    savedResult = snapshot.result;
    draftDate = date;
    $('today-result-text').value = savedResult?.text ?? '';
    $('today-result-ready').checked = savedResult?.status === 'ready';
    $('today-result-evidence').value = savedResult?.evidence ?? '';
    status(savedResult ? (savedResult.status === 'ready' ? 'Результат готов · сохранено' : 'В работе · сохранено') : 'No Data');
    evidenceField();
  }
  $('today-result-label').textContent = `Основной результат · ${dateLabel(draftDate ?? date)}`;
  $('today-add-time').disabled = false;
}
async function load() {
  const id = ++requestId;
  loading = true;
  $('today-result-save').disabled = true;
  try {
    const response = await fetch('/api/today');
    const result = await response.json();
    if (!response.ok) throw new Error(result.error ?? 'Не удалось прочитать сегодняшний день.');
    if (id !== requestId) return;
    snapshot = result;
    $('today-error').hidden = true;
    $('today-retry').hidden = true;
    render();
  } catch (error) {
    if (id !== requestId) return;
    $('today-error').textContent = error.message;
    $('today-error').hidden = false;
    $('today-retry').hidden = false;
  } finally {
    if (id === requestId) { loading = false; $('today-result-save').disabled = saving || !snapshot; }
  }
}
function addTime(metricId = null) {
  if (snapshot) window.dispatchEvent(new CustomEvent('rhythm:add-today-entry', { detail: { date: snapshot.date, metricId } }));
}
$('today-add-time').addEventListener('click', () => addTime());
$('today-norms').addEventListener('click', event => { const button = event.target.closest('[data-today-metric]'); if (button) addTime(button.dataset.todayMetric); });
$('today-retry').addEventListener('click', () => void load());
$('today-result-history').addEventListener('click', () => window.dispatchEvent(new Event('rhythm:show-daily-results')));
$('today-result-form').addEventListener('input', () => {
  if (!draftDate && snapshot) draftDate = snapshot.date;
  dirty = true; status('Не сохранено'); evidenceField();
});
$('today-result-form').addEventListener('submit', async event => {
  event.preventDefault();
  if (saving || loading || !snapshot) return;
  const input = { date: draftDate ?? snapshot.date, text: $('today-result-text').value, status: $('today-result-ready').checked ? 'ready' : 'planned', evidence: $('today-result-evidence').value, expectedUpdatedAt: savedResult?.updatedAt ?? null };
  saving = true;
  $('today-result-save').disabled = true;
  status('Сохраняю…');
  try {
    const response = await fetch('/api/daily-results', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(input) });
    const result = await response.json();
    if (!response.ok) {
      dirty = true;
      const history = await fetch('/api/daily-results');
      if (history.ok) savedResult = (await history.json()).entries.find(item => item.date === input.date) ?? null;
      throw new Error(result.error ?? 'Не удалось сохранить результат.');
    }
    savedResult = result;
    dirty = $('today-result-text').value !== input.text || ($('today-result-ready').checked ? 'ready' : 'planned') !== input.status || $('today-result-evidence').value !== input.evidence;
    status(dirty ? 'Есть несохранённые изменения' : result.status === 'ready' ? 'Результат готов · сохранено' : 'В работе · сохранено');
    window.dispatchEvent(new Event('rhythm:daily-result-saved'));
  } catch (error) { status(error.message, true); }
  finally { saving = false; $('today-result-save').disabled = loading; }
});
for (const event of ['rhythm:week-loaded', 'rhythm:entry-classified', 'focus']) window.addEventListener(event, () => { if (!saving) void load(); });
void load();
