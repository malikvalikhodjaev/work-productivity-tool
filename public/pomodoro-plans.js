const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
import './timer.js';

const today = () => new Date(Date.now() + 5 * 3600000).toISOString().slice(0, 10);
const shift = (d, n) => new Date(Date.parse(`${d}T12:00:00Z`) + n * 86400000).toISOString().slice(0, 10);
const readOnly = Boolean(document.querySelector('meta[name="dashboard-access"][content="viewer"]'));
const embedded = window.parent !== window;
let data, entities = [], selectedWeek = '', loading = false, submitting = false, expected, retryBody;
let promptedDay = '', nextPrompt = 0, entryPending = true;
const host = document.createElement('section');
host.className = 'pomodoro-settings'; host.id = 'pomodoro-settings';
host.innerHTML = `<header class="pom-header"><div><p class="eyebrow">ДНЕВНОЙ ПЛАН</p><h2>Нормативы помидорок</h2></div><button type="button" class="button primary" data-pom-add>＋ Норматив на день</button></header><p class="pom-note">Название — выполнено / запланировано. Счётчик обновляется после учёта полной рабочей помидорки.</p><div data-pom-list></div><p class="pom-status" role="status"></p><details class="pom-week"><summary>Статистика помидорок за неделю</summary><div class="pom-week-nav"><button type="button" class="button secondary" data-pom-week="-7" aria-label="Предыдущая неделя">←</button><span id="pom-week-label"></span><button type="button" class="button secondary" data-pom-week="7" aria-label="Следующая неделя">→</button><button type="button" class="button secondary" data-pom-week="today">Текущая</button></div><div id="pom-week-table" class="pom-table-scroll"></div></details>`;
document.getElementById('timer-panel')?.insertAdjacentElement('afterend', host);
const floating = document.createElement('aside'); floating.className = 'pomodoro-floating'; floating.setAttribute('aria-label', 'Чек-лист помидорок на сегодня');
floating.innerHTML = '<header class="pom-header"><strong>Помидорки · сегодня</strong><button type="button" data-pom-settings aria-label="Настройки дневных норм">⚙</button></header><div data-pom-list></div><button type="button" class="pom-text-button" data-pom-add>＋ Норматив на день</button>';
if (!embedded && !document.body.classList.contains('focus-window')) document.body.append(floating);
const editor = document.createElement('dialog'); editor.className = 'modal pom-editor'; editor.id = 'pomodoro-editor';
editor.innerHTML = `<form><div class="modal-heading"><h2>Норматив помидорок на день</h2><button type="button" class="icon-button" data-pom-close aria-label="Закрыть норматив">×</button></div><label class="field">Дата<input name="date" type="date" required></label><label class="field">Работа / задача / кейс<select name="workRef" required></select></label><label class="field">Название норматива<input name="title" maxlength="240" required></label><label class="field">Помидорок за день<input name="target" type="number" min="1" max="1440" step="1" inputmode="numeric" required></label><p class="pom-note">Фокус запускается по выбранной работе. Норма относится к указанной дате.</p><p class="form-error" role="alert"></p><div class="modal-footer"><button type="button" class="button secondary" id="pom-remove">Снять норматив</button><button type="submit" class="button primary">Сохранить</button></div></form>`;
document.body.append(editor);
const form = editor.querySelector('form'), field = name => form.elements.namedItem(name);
const prompt = document.createElement('dialog'); prompt.className = 'modal pom-planning-prompt';
prompt.innerHTML = '<h2>Вы поставили нормативы на день?</h2><p>На сегодня ещё нет плана помидорок. Задай хотя бы один норматив — этот вопрос перестанет появляться до следующего дня.</p><div class="modal-footer"><button type="button" class="button secondary" id="pom-later">Позже · напомнить через час</button><button type="button" class="button primary" data-pom-add>Задать норматив</button></div>';
document.body.append(prompt);
const settings = document.createElement('dialog'); settings.className = 'modal pom-settings-dialog';
settings.innerHTML = '<div class="modal-heading"><h2>Настройки · помидорки на сегодня</h2><button type="button" class="icon-button" data-pom-settings-close aria-label="Закрыть настройки">×</button></div><div data-pom-list></div><div class="modal-footer"><button type="button" class="button secondary" data-pom-stats>Статистика недели</button><button type="button" class="button primary" data-pom-add>＋ Норматив на день</button></div>';
document.body.append(settings);

async function api(route, body) {
  const response = await fetch(route, {cache:'no-store', ...(body ? {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)} : {})});
  const result = await response.json(); if (!response.ok) throw new Error(result.error ?? 'Не удалось сохранить план.'); return result;
}
function listHtml() {
  const rows = data?.pomodoroPlan?.targets ?? [];
  if (!rows.length) return '<p class="pom-empty">Нормативы на сегодня не заданы.</p>';
  return '<ul class="pom-checklist">' + rows.map(n => `<li class="${n.actualPomodoros >= n.target ? 'pom-done' : ''}"><span class="pom-check" aria-label="${n.actualPomodoros >= n.target ? 'Выполнено' : 'В работе'}">${n.actualPomodoros >= n.target ? '☑' : '☐'}</span><span class="pom-name">${esc(n.title)}</span><strong class="pom-count">${n.actualPomodoros}/${n.target}</strong><button type="button" data-pom-focus="${esc(n.workRef)}" aria-label="Фокус: ${esc(n.title)}">▶</button><button type="button" data-pom-edit="${esc(n.workRef)}" aria-label="Изменить норматив: ${esc(n.title)}">✎</button></li>`).join('') + '</ul>';
}
function render() {
  if (!data) return;
  for (const list of document.querySelectorAll('[data-pom-list]')) list.innerHTML = listHtml();
  const w = data.pomodoroWeek;
  document.getElementById('pom-week-label').textContent = `${w.week} — ${w.end}`;
  document.getElementById('pom-week-table').innerHTML = w.rows.length ? `<table><caption class="sr-only">Помидорки: факт / план по дням</caption><thead><tr><th>Норматив</th>${w.days.map(d => `<th>${d.slice(8)}.${d.slice(5,7)}</th>`).join('')}<th>Неделя</th></tr></thead><tbody>${w.rows.map(row => `<tr><th>${esc(row.title)}</th>${w.days.map(d => { const n=row.days.find(t=>t.date===d); return `<td>${n ? `${n.actualPomodoros}/${n.target}` : '<span title="Норма не задана">—</span>'}</td>`; }).join('')}<td><strong>${row.actualPomodoros}/${row.target}</strong></td></tr>`).join('')}</tbody></table>` : '<p class="pom-empty">No Data — на выбранную неделю нормы ещё не заданы.</p>';
  for (const button of document.querySelectorAll('[data-pom-add],[data-pom-edit],[data-pom-focus]')) button.disabled = readOnly;
  if (data.pomodoroPlan.hasPlan && prompt.open) prompt.close();
}
function maybePrompt(force = false) {
  if (readOnly || embedded || !data || data.today !== today() || data.pomodoroPlan.hasPlan || document.hidden) return;
  if ([...document.querySelectorAll('dialog')].some(d=>d.open)) return;
  if (!force && promptedDay === today() && Date.now() < nextPrompt) return;
  promptedDay = today(); nextPrompt = Date.now() + 3600000; entryPending = false; prompt.showModal();
}
async function load() {
  if (loading) return; loading = true;
  try {
    data = await api('/api/daily-norms' + (selectedWeek ? '?week=' + selectedWeek : ''));
    host.querySelector('.pom-status').textContent = '';
    render(); maybePrompt(entryPending);
  } catch (error) { host.querySelector('.pom-status').textContent = error.message; }
  finally { loading = false; }
}
function previous() { return data?.pomodoroTargets?.find(t => t.date === field('date').value && t.workRef === field('workRef').value); }
function fillPrevious() {
  const row=previous(); expected=row?.updatedAt ?? null;
  field('title').value = row?.title ?? entities.find(e=>e.ref===field('workRef').value)?.title ?? '';
  field('target').value = row?.target ?? 1;
  document.getElementById('pom-remove').hidden = !row || row.target == null;
  retryBody = null;
}
async function edit(ref) {
  if (readOnly || submitting) return;
  try {
    entities = (await api('/api/workspace')).entities;
    if (!entities.length) throw new Error('Сначала создай работу или кейс в разделе «Работа».');
    if (prompt.open) prompt.close();
    field('date').value=today();
    field('workRef').innerHTML=entities.map(e=>`<option value="${esc(e.ref)}">${esc(e.title)}</option>`).join('');
    if (ref) field('workRef').value=ref;
    fillPrevious(); form.querySelector('.form-error').textContent=''; editor.showModal();
  } catch(error) { host.querySelector('.pom-status').textContent=error.message; if (prompt.open) { prompt.querySelector('p').textContent=error.message; } }
}
async function save(remove = false) {
  if (submitting || (!remove && !form.reportValidity())) return;
  const input={date:field('date').value,workRef:field('workRef').value,title:field('title').value,target:remove?null:Number(field('target').value)};
  const content=JSON.stringify({input,expectedUpdatedAt:expected});
  if (!retryBody || retryBody.content!==content) retryBody={content,command:{input,expectedUpdatedAt:expected,requestId:crypto.randomUUID()}};
  submitting=true; for(const b of form.querySelectorAll('button'))b.disabled=true;
  try { await api('/api/pomodoro-plan',retryBody.command); editor.close(); await load(); }
  catch(error) { form.querySelector('.form-error').textContent=error.message; }
  finally { submitting=false; for(const b of form.querySelectorAll('button'))b.disabled=false; }
}
document.addEventListener('click', event => {
  const b=event.target.closest('button'); if(!b)return;
  if(b.hasAttribute('data-pom-add'))void edit();
  if(b.hasAttribute('data-pom-edit'))void edit(b.dataset.pomEdit);
  if(b.hasAttribute('data-pom-settings')) { render(); settings.showModal(); }
  if(b.hasAttribute('data-pom-settings-close'))settings.close();
  if(b.hasAttribute('data-pom-stats')) { settings.close(); location.hash='work'; host.querySelector('details').open=true; host.scrollIntoView({behavior:'smooth',block:'start'}); }
  if(b.hasAttribute('data-pom-focus')) { const row=data?.pomodoroPlan.targets.find(n=>n.workRef===b.dataset.pomFocus); if(row)void window.rhythmTimer?.focus({workRef:row.workRef,title:row.title,mode:'pomodoro'}); }
  if(b.hasAttribute('data-pom-close')&&!submitting)editor.close();
  if(b.hasAttribute('data-pom-week')) { const n=b.dataset.pomWeek; selectedWeek=n==='today'?'':shift(data.pomodoroWeek.week,Number(n)); void load(); }
});
field('date').addEventListener('change',fillPrevious); field('workRef').addEventListener('change',fillPrevious);
form.addEventListener('submit',e=>{e.preventDefault();void save();});
document.getElementById('pom-remove').addEventListener('click',()=>void save(true));
document.getElementById('pom-later').addEventListener('click',()=>{nextPrompt=Date.now()+3600000;prompt.close();});
prompt.addEventListener('cancel',()=>{nextPrompt=Date.now()+3600000;});
for (const name of ['focus','pageshow']) window.addEventListener(name,()=>{entryPending=true;void load();});
document.addEventListener('visibilitychange',()=>{if(!document.hidden){entryPending=true;void load();}});
window.addEventListener('beforeunload',event=>{if(!readOnly&&data&&data.today===today()&&!data.pomodoroPlan.hasPlan){event.preventDefault();event.returnValue='Вы поставили нормативы на день?';}});
window.addEventListener('rhythm:timer-state',event=>{if(event.detail?.changed)void load();});
window.addEventListener('rhythm:week-loaded',event=>{selectedWeek=event.detail.week;void load();});
const timerSettings=document.querySelector('#timer-dialog form');
if(timerSettings){const preview=document.createElement('div');preview.className='pom-settings-preview';preview.innerHTML='<h3>Помидорки на сегодня</h3><div data-pom-list></div><button type="button" class="button secondary" data-pom-add>Задать норматив</button>';timerSettings.append(preview);}
if (!embedded) { setInterval(()=>void load(),15000); void load(); }
