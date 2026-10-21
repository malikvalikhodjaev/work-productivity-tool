const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
import './timer.js';
import { pomodoroCapacityOn, pomodoroCapacitySummary } from './pomodoro-capacity.js';

const today = () => new Date(Date.now() + 5 * 3600000).toISOString().slice(0, 10);
const shift = (d, n) => new Date(Date.parse(`${d}T12:00:00Z`) + n * 86400000).toISOString().slice(0, 10);
const readOnly = Boolean(document.querySelector('meta[name="dashboard-access"][content="viewer"]'));
const embedded = window.parent !== window;
let data, entities = [], selectedWeek = '', loading = false, submitting = false, expected, retryBody, editing = false;
let promptedDay = '', nextPrompt = 0, entryPending = true;
const host = document.createElement('section');
host.className = 'pomodoro-settings'; host.id = 'pomodoro-settings';
host.innerHTML = `<header class="pom-header"><div><p class="eyebrow">ДНЕВНОЙ ПЛАН</p><h2>Нормативы помидорок</h2></div><button type="button" class="button primary" data-pom-add>＋ Ежедневный норматив</button></header><p class="pom-note">Название — выполнено / запланировано. Счётчик обновляется после учёта полной рабочей помидорки.</p><div data-pom-list></div><p class="pom-status" role="status"></p><details class="pom-week"><summary>Статистика помидорок за неделю</summary><div class="pom-week-nav"><button type="button" class="button secondary" data-pom-week="-7" aria-label="Предыдущая неделя">←</button><span id="pom-week-label"></span><button type="button" class="button secondary" data-pom-week="7" aria-label="Следующая неделя">→</button><button type="button" class="button secondary" data-pom-week="today">Текущая</button></div><div id="pom-week-table" class="pom-table-scroll"></div></details>`;
document.getElementById('timer-panel')?.insertAdjacentElement('afterend', host);
const floating = document.createElement('aside'); floating.className = 'pomodoro-floating'; floating.setAttribute('aria-label', 'Чек-лист помидорок на сегодня');
floating.innerHTML = '<header class="pom-header"><strong>Помидорки · сегодня</strong><button type="button" data-pom-settings aria-label="Настройки дневных норм">⚙</button></header><div data-pom-list></div><button type="button" class="pom-text-button" data-pom-add>＋ Ежедневный норматив</button>';
if (!embedded && !document.body.classList.contains('focus-window')) document.body.append(floating);
const editor = document.createElement('dialog'); editor.className = 'modal pom-editor'; editor.id = 'pomodoro-editor';
editor.innerHTML = `<form><div class="modal-heading"><h2>Ежедневный норматив помидорок</h2><button type="button" class="icon-button" data-pom-close aria-label="Закрыть норматив">×</button></div><label class="field">Действует с<input name="date" type="date" required></label><label class="field">Работа / задача / кейс<select name="workRef" required></select></label><label class="field">Название норматива<input name="title" maxlength="240" required></label><label class="field">Помидорок за день<input name="target" type="number" min="1" max="1440" step="1" inputmode="numeric" required></label><p class="pom-note">Фокус запускается по выбранной работе. Ежедневно, без срока окончания — пока не изменишь или не снимешь.</p><p class="form-error" role="alert"></p><div class="modal-footer"><button type="button" class="button secondary" id="pom-remove">Снять норматив</button><button type="submit" class="button primary">Сохранить</button></div></form>`;
document.body.append(editor);
const form = editor.querySelector('form'), field = name => form.elements.namedItem(name);
const prompt = document.createElement('dialog'); prompt.className = 'modal pom-planning-prompt';
prompt.innerHTML = '<h2>Вы поставили нормативы на день?</h2><p>На сегодня ещё нет плана помидорок. Задай хотя бы один ежедневный норматив — он будет повторяться каждый день, пока ты его не снимешь.</p><div class="modal-footer"><button type="button" class="button secondary" id="pom-later">Позже · напомнить через час</button><button type="button" class="button primary" data-pom-add>Задать норматив</button></div>';
document.body.append(prompt);
const settings = document.createElement('dialog'); settings.className = 'modal pom-settings-dialog';
settings.innerHTML = '<div class="modal-heading"><h2>Настройки · помидорки на сегодня</h2><button type="button" class="icon-button" data-pom-settings-close aria-label="Закрыть настройки">×</button></div><div data-pom-list></div><div class="modal-footer"><button type="button" class="button secondary" data-pom-stats>Статистика недели</button><button type="button" class="button primary" data-pom-add>＋ Ежедневный норматив</button></div>';
document.body.append(settings);

const capacityEditor = document.createElement('dialog'); capacityEditor.className='modal pom-editor';
capacityEditor.innerHTML='<form><h2>Дневной лимит по силам</h2><p class="pom-note">Твой максимум на сумму всех нормативов. Повторяется каждый день с выбранной даты. Превышение подсвечивается; таймер и учёт времени остаются доступны.</p><label class="field">Действует с<input name="date" type="date" required></label><label class="field">Максимум помидорок в день · пусто для снятия<input name="limit" type="number" min="1" max="1440" step="1" inputmode="numeric"></label><p class="form-error" role="alert"></p><div class="modal-footer"><button type="button" class="button secondary" data-cap-close>Закрыть</button><button type="submit" class="button primary">Сохранить</button></div></form>';
document.body.append(capacityEditor);
let capacityRetry, capacitySaving=false, capacityBase=[];
for(const container of [host,settings]) {
  const button=document.createElement('button'); button.type='button'; button.className='button secondary';
  button.dataset.pomCapacity=''; button.textContent='Дневной лимит по силам'; button.disabled=readOnly;
  container.querySelector('[data-pom-list]').insertAdjacentElement('beforebegin',button);
}
const capacityPreview=document.createElement('p'); capacityPreview.className='pom-capacity'; capacityPreview.setAttribute('role','status');
form.querySelector('.form-error').insertAdjacentElement('beforebegin',capacityPreview);
const capacityHtml = summary => `<p class="pom-capacity ${summary?.over?'pom-over':''}" role="status">${esc(summary?.message ?? '')}</p>`;
function updateCapacityPreview() {
  const day=field('date').value, selected=field('workRef').value, value=field('target').value;
  const summary=pomodoroCapacitySummary(targetsOn(day),data?.pomodoroCapacities,day,
    selected && value!=='' && Number.isInteger(Number(value)) ? {workRef:selected,target:Number(value)} : null);
  capacityPreview.textContent=summary.message; capacityPreview.classList.toggle('pom-over',summary.over);
}
function targetsOn(day) {
  const selected=new Map();
  for(const row of data?.pomodoroTargets??[]) {
    if(row.date!==day&&!(row.repeat==='daily'&&row.date<=day))continue;
    if(!selected.has(row.workRef)||row.date>selected.get(row.workRef).date)selected.set(row.workRef,row);
  }
  return [...selected.values()].filter(t=>t.target!=null);
}
function editCapacity() {
  if(readOnly||capacitySaving||!data)return;
  const cf=capacityEditor.querySelector('form'); capacityBase=structuredClone(data.pomodoroCapacities??[]);
  cf.elements.date.value=today(); cf.elements.limit.value=pomodoroCapacityOn(capacityBase,today())??'';
  cf.querySelector('.form-error').textContent=''; capacityRetry=null; capacityEditor.showModal();
}
capacityEditor.querySelector('form').addEventListener('submit',async event=>{
  event.preventDefault(); if(capacitySaving||readOnly)return;
  const cf=event.currentTarget; if(!cf.reportValidity())return;
  const input={date:cf.elements.date.value,limit:cf.elements.limit.value===''?null:Number(cf.elements.limit.value)};
  const content=JSON.stringify({input,expectedUpdatedAt:capacityBase.find(r=>r.date===input.date)?.updatedAt??null});
  if(capacityRetry?.content!==content)capacityRetry={content,command:{...JSON.parse(content),requestId:crypto.randomUUID()}};
  capacitySaving=true; for(const b of cf.querySelectorAll('button'))b.disabled=true;
  try { await api('/api/pomodoro-capacity',capacityRetry.command); capacityEditor.close(); await load(); }
  catch(error){cf.querySelector('.form-error').textContent=error.message;}
  finally{capacitySaving=false;for(const b of cf.querySelectorAll('button'))b.disabled=false;}
});

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
  for (const list of document.querySelectorAll('[data-pom-list]')) list.innerHTML = capacityHtml(data.pomodoroPlan.capacity)+listHtml();
  const w = data.pomodoroWeek;
  document.getElementById('pom-week-label').textContent = `${w.week} — ${w.end}`;
  document.getElementById('pom-week-table').innerHTML = w.rows.length ? `<table><caption class="sr-only">Помидорки: факт / план по дням</caption><thead><tr><th>Норматив</th>${w.days.map(d => `<th>${d.slice(8)}.${d.slice(5,7)}</th>`).join('')}<th>Неделя</th></tr></thead><tbody>${w.rows.map(row => `<tr><th>${esc(row.title)}</th>${w.days.map(d => { const n=row.days.find(t=>t.date===d); return `<td>${n ? `${n.actualPomodoros}/${n.target}` : '<span title="Норма не задана">—</span>'}</td>`; }).join('')}<td><strong>${row.actualPomodoros}/${row.target}</strong></td></tr>`).join('')}</tbody></table>` : '<p class="pom-empty">No Data — на выбранную неделю нормы ещё не заданы.</p>';
  document.getElementById('pom-week-table').insertAdjacentHTML('afterbegin',
    '<p class="pom-note">Суммарный план / дневной лимит · «—» — лимит не задан</p><div class="pom-capacity-week">'+
    (w.capacities??[]).map(c=>`<span class="pom-capacity ${c.over?'pom-over':''}" title="${esc(c.message)}">${c.date.slice(8)}.${c.date.slice(5,7)} · ${c.planned} / ${c.limit??'—'}</span>`).join('')+'</div>');
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
  const exact=previous(), row=exact??data?.pomodoroPlan.targets.find(t=>t.workRef===field('workRef').value&&t.repeat==='daily'&&t.sourceDate<=field('date').value); expected=exact?.updatedAt ?? null;
  field('title').value = (editing ? row?.title : null) ?? entities.find(e=>e.ref===field('workRef').value)?.title ?? '';
  field('target').value = (editing ? row?.target : null) ?? 1;
  document.getElementById('pom-remove').hidden = !editing || !row || row.target == null;
  form.querySelector('.form-error').textContent=!editing&&row?.target!=null?'Для этой работы уже есть норматив. Выбери другую карточку; прежнюю норму можно изменить через карандаш.':'';
  retryBody = null;
  updateCapacityPreview();
}
async function edit(ref) {
  if (readOnly || submitting) return;
  try {
    entities = (await api('/api/workspace')).entities;
    if (!entities.length) throw new Error('Сначала создай работу или кейс в разделе «Работа».');
    if (prompt.open) prompt.close();
    editing=Boolean(ref);
    form.querySelector('h2').textContent=editing?'Изменить ежедневный норматив':'Добавить ежедневный норматив';
    field('date').value=today();
    field('workRef').innerHTML='<option value="">Выбери работу для отдельного счётчика</option>'+entities.map(e=>`<option value="${esc(e.ref)}">${esc(e.title)}</option>`).join('');
    field('workRef').disabled=editing;
    if (ref) field('workRef').value=ref;
    fillPrevious(); editor.showModal();
  } catch(error) { host.querySelector('.pom-status').textContent=error.message; if (prompt.open) { prompt.querySelector('p').textContent=error.message; } }
}
async function save(remove = false) {
  if (submitting || (!remove && !form.reportValidity())) return;
  const input={date:field('date').value,workRef:field('workRef').value,title:field('title').value,target:remove?null:Number(field('target').value),repeat:'daily',...(!editing?{create:true}:{})};
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
  if(b.hasAttribute('data-pom-capacity'))editCapacity();
  if(b.hasAttribute('data-cap-close')&&!capacitySaving)capacityEditor.close();
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
field('target').addEventListener('input',updateCapacityPreview);
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
