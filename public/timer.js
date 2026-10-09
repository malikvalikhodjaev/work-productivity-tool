const $ = id => document.getElementById(id);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const duration = seconds => { if (seconds === null) return 'No Data'; const n = Math.max(0, Math.floor(seconds)); return `${Math.floor(n / 3600) ? Math.floor(n / 3600) + ':' : ''}${String(Math.floor(n / 60) % 60).padStart(2,'0')}:${String(n % 60).padStart(2,'0')}`; };
const number = new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 2 });
const humanTime = seconds => { const n=Math.round(seconds); return [Math.floor(n/3600) ? `${Math.floor(n/3600)} ч` : '',Math.floor(n/60)%60 ? `${Math.floor(n/60)%60} мин` : '',n%60 || n===0 ? `${n%60} с` : ''].filter(Boolean).join(' '); };
const embedded = window.parent !== window;
const readOnly = Boolean(document.querySelector('meta[name="dashboard-access"][content="viewer"]'));
let state, serverOffset = 0, week, entities = [], metrics = [], busy = false, loading = false, alarmId;
const panel = document.createElement('section');
panel.className = 'timer-panel'; panel.id = 'timer-panel';
panel.innerHTML = `<div class="timer-heading"><div><p class="eyebrow">РАБОТА → ВРЕМЯ → НОРМАТИВ</p><h2>Фокус и время</h2></div><button class="button primary" id="timer-new" type="button">Запустить таймер</button></div><p id="timer-status" class="timer-note" role="status">Загрузка…</p><div id="timer-active" hidden><div class="timer-current"><div><p id="timer-phase" class="eyebrow"></p><h3 id="timer-title"></h3><p id="timer-link" class="timer-note"></p></div><output id="timer-clock" class="timer-clock" aria-label="Отсчёт таймера"></output></div><p id="timer-warning" class="timer-note"></p><div class="timer-actions"><button id="timer-pause" class="button secondary" type="button">Пауза</button><button id="timer-extend" class="button secondary" type="button">＋ 5 минут</button><button id="timer-finish" class="button primary" type="button">Завершить и учесть</button><button id="timer-cancel" class="text-button" type="button">Отменить сеанс</button></div></div><div id="timer-idle" class="timer-idle" hidden><p>Выбери карточку работы или назови активность. Время учтётся после завершения.</p><button id="timer-break" class="button secondary" type="button">Начать перерыв</button><span id="timer-cycle" class="timer-note"></span></div><div id="timer-summary" class="timer-summary"></div><details class="timer-details"><summary>Статистика недели и норматив конкретной работы</summary><p id="timer-week" class="timer-note"></p><div id="timer-plans"></div><form id="timer-plan-form" class="timer-plan-form"><label>Работа<select id="timer-plan-ref" required></select></label><label>Часов в эту неделю<input id="timer-plan-hours" type="number" min="0.01" max="168" step="0.01" inputmode="decimal"></label><button class="button secondary" type="submit">Сохранить норматив</button></form><p class="timer-note">Пустое поле снимает норматив. В факт входит всё связанное время, включая ручные записи и импорт. Этот разрез не добавляет часы второй раз.</p><div id="timer-by-work"></div><details><summary>Сеансы таймера</summary><div class="timer-table-wrap"><table class="timer-table"><thead><tr><th>Начало</th><th>Работа</th><th>Состояние</th><th>Время</th><th>Помидорки</th></tr></thead><tbody id="timer-history"></tbody></table></div></details></details><p id="timer-backup" class="timer-note"></p>`;
if (!embedded) ($('work-panel') ?? document.querySelector('main') ?? document.body).prepend(panel);
const dialog = document.createElement('dialog'); dialog.id = 'timer-dialog'; dialog.className = 'modal timer-dialog';
dialog.innerHTML = `<form id="timer-form"><div class="modal-heading"><h2>Таймер работы</h2><button class="icon-button" id="timer-close" type="button" aria-label="Закрыть таймер">×</button></div><label class="field">Что делаю<input id="timer-input-title" maxlength="300" required></label><label class="field">Связанная работа / объект<select id="timer-input-ref"></select></label><div class="field-pair"><label class="field">Учесть время<select id="timer-input-metric"></select></label><label class="field">Характер работы<input id="timer-input-type" list="work-types" maxlength="80"></label></div><div class="field-pair"><label class="field">Режим<select id="timer-mode"><option value="pomodoro">Помидорка</option><option value="stopwatch">Секундомер</option></select></label><label class="field">Пресет<select id="timer-preset"><option value="custom">Мои настройки</option><option value="25">25 / 5 минут</option><option value="50">50 / 10 минут</option></select></label></div><div class="timer-settings"><label class="field">Работа, мин<input id="timer-work" type="number" min="1" max="240" step="1" required></label><label class="field">Перерыв, мин<input id="timer-short" type="number" min="1" max="240" step="1" required></label><label class="field">Длинный, мин<input id="timer-long" type="number" min="1" max="240" step="1" required></label><label class="field">После помидорок<input id="timer-every" type="number" min="1" max="20" step="1" required></label></div><p class="timer-note">Настройки применяются к новому сеансу. Перерывы запускаются отдельно и не входят в рабочие часы. Сигнал работает на открытой странице; на заблокированном Android проверка ещё нужна.</p><p id="timer-error" class="form-error" role="alert" hidden></p><div class="modal-footer"><button id="timer-save-settings" class="button secondary" type="button">Сохранить настройки</button><button id="timer-start" class="button primary" type="submit">Начать работу</button></div></form>`;
if (!embedded) document.body.append(dialog);
const finishDialog = document.createElement('dialog'); finishDialog.className = 'modal timer-dialog'; finishDialog.id = 'timer-finish-dialog';
finishDialog.innerHTML = `<form id="timer-finish-form"><div class="modal-heading"><h2>Подтвердить время</h2><button id="timer-finish-close" class="icon-button" type="button" aria-label="Закрыть подтверждение">×</button></div><p class="timer-note">Проверь фактическое время. Паузы и время после конца помидорки уже исключены. Можно уменьшить факт, если отвлекался.</p><label class="field">Сколько секунд действительно работал<input id="timer-worked-seconds" type="number" min="0" max="86400" step="1" required></label><p id="timer-worked-label" class="timer-note"></p><p id="timer-finish-error" class="form-error" role="alert" hidden></p><div class="modal-footer"><button class="button primary" type="submit">Подтвердить и учесть</button></div></form>`;
if (!embedded) document.body.append(finishDialog);
const pill = document.createElement('button'); pill.id = 'timer-pill'; pill.className = 'timer-pill'; pill.type = 'button'; pill.hidden = true;
if (!embedded) document.body.append(pill);
async function get(url) { const response = await fetch(url, {cache:'no-store'}); const data = await response.json(); if (!response.ok) throw new Error(data.error ?? 'Не удалось прочитать таймер.'); return data; }
function notice(message, error = false) { $('timer-status').textContent = message; $('timer-status').classList.toggle('timer-error',error); }
function settings() { return { workMinutes:Number($('timer-work').value), shortBreakMinutes:Number($('timer-short').value), longBreakMinutes:Number($('timer-long').value), longBreakEvery:Number($('timer-every').value) }; }
function now() { return Date.now() + serverOffset; }
function elapsed(s) { const past = s.intervals.reduce((n,i) => n+i.end-i.start,0); const run = s.status === 'running' ? Math.max(0,now()-s.runningSince) : 0; return past + (s.mode === 'pomodoro' ? Math.min(run,Math.max(0,s.plannedMs-past)) : run); }
function tick() {
  if (!state?.active) return;
  const s = state.active, ms = elapsed(s), expired = s.mode === 'pomodoro' && ms >= s.plannedMs;
  const clock = duration((s.mode === 'pomodoro' ? Math.max(0,s.plannedMs-ms) : ms)/1000);
  $('timer-clock').textContent = clock; pill.textContent = `${s.status === 'paused' ? 'Ⅱ' : '◷'} ${clock} · ${s.title}`;
  $('timer-warning').textContent = s.status === 'paused' ? 'Пауза · время не учитывается' : expired ? 'Интервал закончился. Заверши, чтобы учесть время, или добавь 5 минут.' : `Учтено ${duration(ms/1000)} · отсчёт сохраняется на сервере`;
  $('timer-pause').disabled = busy || (expired && s.status === 'paused');
  if (expired && s.status === 'running' && alarmId !== s.id) {
    alarmId = s.id;
    try { const audio = new (window.AudioContext ?? window.webkitAudioContext)(); const tone = audio.createOscillator(), gain = audio.createGain(); tone.connect(gain); gain.connect(audio.destination); gain.gain.value = 0.08; tone.frequency.value = 660; tone.start(); tone.stop(audio.currentTime+0.3); tone.onended=()=>void audio.close(); } catch {}
    if ('Notification' in window && Notification.permission === 'granted') try { new Notification('Интервал завершён', {body:s.title,tag:s.id}); } catch {}
  }
}
function render() {
  const s = state.active;
  $('timer-active').hidden = !s; $('timer-idle').hidden = Boolean(s); $('timer-new').disabled = Boolean(s)||busy; pill.hidden = !s;
  $('timer-cycle').textContent = `В цикле: ${state.cycleCount} · длинный перерыв после ${state.settings.longBreakEvery}`;
  $('timer-break').textContent = state.cycleCount >= state.settings.longBreakEvery ? `Длинный перерыв · ${state.settings.longBreakMinutes} мин` : `Начать перерыв · ${state.settings.shortBreakMinutes} мин`;
  if (s) {
    $('timer-title').textContent=s.title; $('timer-phase').textContent= s.phase === 'work' ? (s.mode === 'pomodoro' ? 'ПОМИДОРКА' : 'СЕКУНДОМЕР') : s.phase === 'long_break' ? 'ДЛИННЫЙ ПЕРЕРЫВ' : 'КОРОТКИЙ ПЕРЕРЫВ';
    $('timer-link').textContent=[entities.find(e=>e.ref===s.workRef)?.title, metrics.find(m=>m.id===s.metricId)?.title ?? (s.allocation==='outside'?'Вне нормативов':s.phase==='work'?'Требует разбора':'Перерыв'),s.workType].filter(Boolean).join(' · ');
    $('timer-pause').textContent=s.status==='paused'?'Продолжить':'Пауза'; $('timer-extend').hidden=s.mode!=='pomodoro'; $('timer-finish').textContent=s.phase==='work'?'Завершить и учесть':'Завершить перерыв';
  }
  $('timer-summary').innerHTML=`<div><small>Работа за неделю</small><strong>${state.summary.workSeconds===null?'No Data':duration(state.summary.workSeconds)}</strong></div><div><small>Полные помидорки</small><strong>${state.summary.records?state.summary.pomodoros:'No Data'}</strong></div><div><small>Перерывы</small><strong>${state.sessions.some(s=>s.phase!=='work')?duration(state.summary.breakSeconds):'No Data'}</strong></div>`;
  $('timer-week').textContent=`${state.week} — ${state.end} · Ташкент, UTC+5`;
  $('timer-plans').innerHTML=state.plans.map(p=>`<div class="timer-plan"><strong>${esc(p.title)}</strong><span>${p.actual===null?'No Data':humanTime(p.actual*3600)} / ${humanTime(p.target*3600)} · ${p.percent===null?'No Data':p.percent+'%'}</span><progress max="100" value="${Math.min(100,p.percent??0)}" aria-label="${esc(p.title)}"></progress></div>`).join('')||'<p class="timer-note">Норматив конкретной работы: No Data</p>';
  $('timer-by-work').innerHTML='<h3>Куда ушло время таймера</h3>'+(state.byWork.map(w=>`<div class="timer-work-row"><span>${esc(w.title)}</span><strong>${duration(w.seconds)}</strong></div>`).join('')||'<p>No Data</p>');
  $('timer-history').innerHTML=state.sessions.map(s=>`<tr><td>${esc(new Date(s.startedAt).toLocaleString('ru-RU',{timeZone:'Asia/Tashkent'}))}</td><td>${esc(s.title)}</td><td>${s.status==='cancelled'?'Отменён, не учтён':s.phase==='work'?'Учтён':'Перерыв'}</td><td>${duration(s.elapsedMs/1000)}</td><td>${s.completedPomodoros}</td></tr>`).join('')||'<tr><td colspan="5">No Data</td></tr>';
  tick();
  if(readOnly) for(const control of panel.querySelectorAll('button,input,select')) control.disabled=true;
}
function accept(value) { if(state && value.revision<state.revision) return; state=value; serverOffset=Date.parse(value.serverNow)-Date.now(); render(); }
async function load() {
  if (loading||busy||embedded) return; loading=true;
  try { accept(await get('/api/timer'+(week?'?week='+encodeURIComponent(week):''))); notice('Сохраняется на ПК · один активный сеанс для всех устройств'); }
  catch(error) { notice(error.message+' Отсчёт на экране может быть устаревшим.',true); }
  finally { loading=false; }
}
async function act(action,input={}) {
  if(readOnly) { notice('Режим просмотра. Изменения доступны в рабочей версии.'); return false; }
  if (busy||!state) return false; busy=true;
  for (const b of panel.querySelectorAll('button')) b.disabled=true;
  $('timer-start').disabled=true; $('timer-save-settings').disabled=true;
  const payload={action,input:{...input,week:state.week,expectedRevision:state.revision,requestId:crypto.randomUUID()}};
  try {
    // Повтор одного запроса после потери ответа безопасен: requestId сохраняется на сервере.
    let response;
    try { response=await fetch('/api/timer',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}); }
    catch { response=await fetch('/api/timer',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}); }
    const result=await response.json(); if(!response.ok) throw new Error(result.error??'Не удалось сохранить сеанс.');
    accept(result); notice('Сохранено на ПК');
    if(action==='finish'||action==='workTarget') window.dispatchEvent(new Event('rhythm:entry-classified'));
    return true;
  } catch(error) { notice(error.message,true); for(const id of ['timer-error','timer-finish-error']) { $(id).textContent=error.message; $(id).hidden=false; } return false; }
  finally { busy=false; for(const b of panel.querySelectorAll('button')) b.disabled=false; $('timer-start').disabled=false; $('timer-save-settings').disabled=false; render(); }
}
async function context() {
  const [workspace,plan]=await Promise.all([get('/api/workspace'),get('/api/dashboard'+(week?'?week='+encodeURIComponent(week):''))]); entities=workspace.entities; metrics=plan.metrics.filter(m=>m.unit==='hours');
  const opts='<option value="">Без связи · отдельная активность</option>'+entities.map(e=>`<option value="${esc(e.ref)}">${esc(e.title)}</option>`).join('');
  const planRef=$('timer-plan-ref').value; $('timer-plan-ref').innerHTML='<option value="">Выбери работу</option>'+entities.map(e=>`<option value="${esc(e.ref)}">${esc(e.title)}</option>`).join(''); $('timer-plan-ref').value=planRef;
  $('timer-input-ref').innerHTML=opts;
  $('timer-input-metric').innerHTML='<option value="unclassified">Требует разбора</option><option value="outside">Вне нормативов</option>'+metrics.map(m=>`<option value="${esc(m.id)}">${esc(m.title)}</option>`).join('');
  if(state) render();
}
async function open(input={}) {
  if(readOnly) return;
  if(embedded) { parent.postMessage({type:'rhythm:timer-work',work:input},location.origin); return; }
  window.dispatchEvent(new Event('rhythm:show-work'));
  await load(); if(!state) return;
  if(state.active) { panel.scrollIntoView({behavior:'smooth',block:'start'}); notice('Сначала заверши текущий сеанс или отмени его.'); return; }
  try { await context(); } catch(error) { notice(error.message,true); return; }
  $('timer-input-title').value=(input.title??'').slice(0,300); $('timer-input-ref').value=input.workRef??''; $('timer-input-type').value=input.workType??'';
  $('timer-input-metric').value=input.metricId??'unclassified'; $('timer-mode').value='pomodoro'; $('timer-preset').value='custom';
  for(const [id,key] of [['work','workMinutes'],['short','shortBreakMinutes'],['long','longBreakMinutes'],['every','longBreakEvery']]) $('timer-'+id).value=state.settings[key];
  $('timer-error').hidden=true; dialog.showModal();
}
function beginFinish() {
  const s=state?.active; if(!s||busy) return;
  const ms=elapsed(s), past=s.intervals.reduce((n,i)=>n+i.end-i.start,0);
  const delayed=s.status==='running' && (s.mode==='pomodoro'?now()-s.runningSince-Math.max(0,s.plannedMs-past)>300000:ms>8*3600000);
  if(s.phase==='work' && (delayed||ms>86400000)) { $('timer-worked-seconds').value=Math.min(86400,Math.floor(ms/1000)); $('timer-worked-seconds').max=Math.min(86400,Math.floor(ms/1000)); $('timer-worked-label').textContent='По отсчёту: '+duration(ms/1000); $('timer-finish-error').hidden=true; finishDialog.showModal(); }
  else void act('finish',{sessionId:s.id});
}
if(!embedded) {
  $('timer-new').addEventListener('click',()=>void open()); pill.addEventListener('click',()=>{ window.dispatchEvent(new Event('rhythm:show-work')); panel.scrollIntoView({behavior:'smooth'}); });
  $('timer-close').addEventListener('click',()=>dialog.close()); $('timer-finish-close').addEventListener('click',()=>finishDialog.close());
  $('timer-preset').addEventListener('change',()=>{ const n=Number($('timer-preset').value); if(n) { $('timer-work').value=n; $('timer-short').value=n===25?5:10; $('timer-long').value=n===25?15:30; $('timer-every').value=4; } });
  $('timer-save-settings').addEventListener('click',async()=>{ if(await act('settings',{settings:settings()})) dialog.close(); });
  $('timer-form').addEventListener('submit',async event=>{ event.preventDefault(); const chosen=$('timer-input-metric').value;
    if(await act('start',{title:$('timer-input-title').value,workRef:$('timer-input-ref').value||null,workType:$('timer-input-type').value,metricId:['outside','unclassified'].includes(chosen)?null:chosen,allocation:chosen,mode:$('timer-mode').value,settings:settings()})) { dialog.close(); if('Notification' in window && Notification.permission==='default') void Notification.requestPermission().catch(()=>{}); }
  });
  $('timer-pause').addEventListener('click',()=>{ if(state?.active) void act(state.active.status==='paused'?'resume':'pause',{sessionId:state.active.id}); });
  $('timer-extend').addEventListener('click',()=>{ if(state?.active) { alarmId=null; void act('extend',{sessionId:state.active.id}); } });
  $('timer-finish').addEventListener('click',beginFinish);
  $('timer-cancel').addEventListener('click',()=>{ if(state?.active && confirm('Отменить сеанс? Время не попадёт в норматив. Сеанс останется в истории.')) void act('cancel',{sessionId:state.active.id}); });
  $('timer-break').addEventListener('click',()=>void act('startBreak'));
  $('timer-finish-form').addEventListener('submit',async event=>{ event.preventDefault(); if(!state?.active) { finishDialog.close(); notice('Сеанс уже завершён на другом устройстве.'); return; } if(await act('finish',{sessionId:state.active.id,workedSeconds:Number($('timer-worked-seconds').value)})) finishDialog.close(); });
  $('timer-plan-ref').addEventListener('change',()=>{ $('timer-plan-hours').value=state.plans.find(p=>p.workRef===$('timer-plan-ref').value)?.target??''; });
  $('timer-plan-form').addEventListener('submit',event=>{ event.preventDefault(); void act('workTarget',{workRef:$('timer-plan-ref').value,hours:$('timer-plan-hours').value===''?null:Number($('timer-plan-hours').value)}); });
  window.addEventListener('rhythm:week-loaded',event=>{ week=event.detail.week; void load(); });
  for(const name of ['focus','rhythm:portfolio-saved']) window.addEventListener(name,()=>{ void load(); if(!dialog.open) void context().catch(()=>{}); });
  document.addEventListener('visibilitychange',()=>{ if(!document.hidden) void load(); });
  setInterval(tick,250); setInterval(()=>{ if(!document.hidden) void load(); },3000);
  void load(); void context().catch(error=>notice(error.message,true));
  void get('/api/server-status').then(s=>{ $('timer-backup').textContent=s.backup.lastSuccess?'Резервная копия: '+new Date(s.backup.lastSuccess).toLocaleString('ru-RU',{timeZone:'Asia/Tashkent'}) : 'Резервная копия: No Data'; }).catch(()=>{});
}
document.addEventListener('click',event=>{ const button=event.target.closest('[data-timer-work]'); if(button) void open({workRef:button.dataset.timerWork,title:button.dataset.timerTitle}); });
window.addEventListener('rhythm:timer-work',event=>void open(event.detail));
window.addEventListener('message',event=>{ if(event.origin===location.origin&&event.source===$('alpha-modeler-frame')?.contentWindow&&event.data?.type==='rhythm:timer-work') void open(event.data.work); });
window.rhythmTimer={open};
