const byId = id => document.getElementById(id);
const escapeHtml = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const number = new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 2 });
let period = '7d';
let overview = null;
let editedIndicator = null;
let requestId = 0;

function dateLabel(value) {
  return new Date(`${value}T12:00:00Z`).toLocaleDateString('ru-RU', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
}

function renderIndicator(item) {
  const observed = item.score !== null;
  const assessment = observed ? `${item.score}/10` : 'No Data';
  const details = observed ? `Оценка от ${dateLabel(item.assessedAt)}` : 'В этом периоде оценки нет';
  const note = item.note && item.note !== 'Исходная оценка из личного описания.' ? `<p class="assessment-note"><strong>Заметка:</strong> ${escapeHtml(item.note)}</p>` : '';
  return `<article class="assessment-card"><div class="assessment-top"><h3>${escapeHtml(item.title)}</h3></div><div class="assessment-score"><strong>${assessment}</strong><small>цель ${item.targetMin}–${item.targetMax}</small></div><div class="assessment-track" role="progressbar" aria-label="${escapeHtml(item.title)}" aria-valuemin="0" aria-valuemax="10" ${observed ? `aria-valuenow="${item.score}"` : ''} aria-valuetext="${escapeHtml(assessment)}"><div class="assessment-target-band"></div><div class="assessment-fill" style="width:${observed ? item.score * 10 : 0}%"></div></div><div class="assessment-date">${escapeHtml(details)}</div><details class="assessment-details"><summary>Что улучшить</summary><p>${escapeHtml(item.context)}</p><p class="assessment-next"><strong>Действие:</strong> ${escapeHtml(item.nextStep)}</p>${note}</details><button class="text-button" type="button" data-assess="${item.id}">Оценить →</button></article>`;
}

function render() {
  if (!overview) return;
  const { activity, assessment } = overview;
  byId('period-date-label').textContent = activity.start === activity.end ? dateLabel(activity.end) : `${dateLabel(activity.start)} — ${dateLabel(activity.end)}`;
  byId('assessment-grid').innerHTML = assessment.indicators.map(renderIndicator).join('');
  for (const [id, metricId] of [['financial-house-hours', 'house_sale'], ['financial-business-hours', 'business']]) {
    const metric = activity.metrics.find(item => item.id === metricId);
    byId(id).textContent = metric?.recordCount ? `${number.format(metric.actual)} ч` : 'No Data';
  }
  byId('financial-period-label').textContent = `За ${activity.start === activity.end ? dateLabel(activity.end) : `${dateLabel(activity.start)} — ${dateLabel(activity.end)}`}`;
  document.querySelectorAll('[data-period]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.period === period)));
}

async function loadOverview(nextPeriod = period) {
  const currentRequest = ++requestId;
  period = nextPeriod;
  document.querySelectorAll('[data-period]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.period === period)));
  try {
    const response = await fetch(`/api/overview?period=${encodeURIComponent(period)}`);
    if (!response.ok) throw new Error('Не удалось получить показатели.');
    const result = await response.json();
    if (currentRequest !== requestId) return;
    overview = result;
    render();
  } catch (error) {
    if (currentRequest !== requestId) return;
    byId('period-date-label').textContent = 'No Data';
    byId('assessment-grid').innerHTML = `<div class="assessment-empty">${escapeHtml(error.message)}</div>`;
    byId('financial-house-hours').textContent = 'No Data';
    byId('financial-business-hours').textContent = 'No Data';
  }
}

function openAssessment(id) {
  const item = overview?.assessment.indicators.find(indicator => indicator.id === id);
  if (!item) return;
  editedIndicator = id;
  byId('indicator-form').reset();
  byId('indicator-dialog-title').textContent = item.title;
  byId('indicator-date').value = overview.activity.end;
  byId('indicator-score').value = item.assessedAt === overview.activity.end ? item.score ?? '' : '';
  byId('indicator-note').value = item.assessedAt === overview.activity.end && item.note !== 'Исходная оценка из личного описания.' ? item.note ?? '' : '';
  byId('indicator-error').hidden = true;
  byId('indicator-dialog').showModal();
}

byId('quick-periods').addEventListener('click', event => {
  const button = event.target.closest('[data-period]');
  if (button) void loadOverview(button.dataset.period);
});
byId('assessment-grid').addEventListener('click', event => {
  const button = event.target.closest('[data-assess]');
  if (button) openAssessment(button.dataset.assess);
});
byId('assessment-history').addEventListener('click', () => window.dispatchEvent(new Event('rhythm:show-assessments')));
byId('indicator-form').addEventListener('submit', async event => {
  event.preventDefault();
  const button = event.currentTarget.querySelector('button[type=submit]');
  button.disabled = true;
  byId('indicator-error').hidden = true;
  try {
    const response = await fetch('/api/indicator-ratings', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ indicatorId: editedIndicator, date: byId('indicator-date').value, score: Number(byId('indicator-score').value), note: byId('indicator-note').value }) });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error ?? 'Не удалось сохранить оценку.');
    byId('indicator-dialog').close();
    await loadOverview();
  } catch (error) {
    byId('indicator-error').textContent = error.message;
    byId('indicator-error').hidden = false;
  } finally { button.disabled = false; }
});
window.addEventListener('rhythm:week-loaded', () => { void loadOverview(); });
void loadOverview();
