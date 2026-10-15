import { createDeviceStore } from './offline-store.js';
import { sessionView } from './timer-core.js';
import { syncDevice } from './offline-engine.js';
import {mountFocusAmbience} from './focus-ambience.js';

const $ = id => document.getElementById(id), store = createDeviceStore();
const channel = 'BroadcastChannel' in window ? new BroadcastChannel('indicators-work-device') : null;
const readOnly = document.querySelector('meta[name="dashboard-access"]')?.content === 'viewer';
let state, syncing = false, acting = false, status = 'Локальное хранилище', formInitialized = false, alarmId, reviewKey, finishSessionId, leisureSessionId, leisurePromptKey, returnSessionId;
const esc = value => String(value ?? '').replace(/[&<>"']/g,c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const duration = ms => { const s = Math.floor(Math.max(0,ms)/1000); return [Math.floor(s/3600),Math.floor(s/60)%60,s%60].map(n=>String(n).padStart(2,'0')).join(':'); };
const ambience=mountFocusAmbience(document.querySelector('main'),{allowExpand:false});$('clock').textContent='00:25:00';
const stamp = value => new Date(value).toLocaleString('ru-RU',{timeZone:'Asia/Tashkent'});
const message = value => { $('message').textContent = value; $('message').hidden = !value; };
const active = () => state?.timer.sessions.find(s=>s.id===state.timer.activeId);
const resting = s => s?.status==='paused'&&Boolean(s.leisure);
const leisureDialog=document.createElement('dialog');leisureDialog.className='modal';
leisureDialog.innerHTML='<form id="leisure-form"><h2>Leisure · до какого времени?</h2><label>Время окончания · Ташкент, UTC+5<input id="leisure-until" type="datetime-local" required></label><p>Работа будет на паузе до нажатия «Вернуться к работе».</p><p id="leisure-error" role="alert"></p><div class="toolbar"><button id="leisure-close" class="secondary" type="button">Закрыть</button><button type="submit">Начать отдых</button></div></form>';
const returnDialog=document.createElement('dialog');returnDialog.className='modal';
returnDialog.innerHTML='<h2>Вернуться к работе?</h2><p id="leisure-title"></p><p>Leisure закончилось. Рабочий таймер остаётся на паузе до твоего нажатия.</p><div class="toolbar"><button id="leisure-later" class="secondary" type="button">Позже</button><button id="leisure-return" type="button">Вернуться к работе</button></div>';
document.body.append(leisureDialog,returnDialog);
const leisureButton=document.createElement('button');leisureButton.type='button';leisureButton.className='secondary';leisureButton.textContent='Leisure';$('pause').after(leisureButton);
leisureButton.addEventListener('click',()=>{
  const s=active();if(!s||acting||readOnly)return;
  leisureSessionId=s.id;$('leisure-error').textContent='';
  $('leisure-until').value=new Date((s.leisure?.until??Date.now()+15*60000)+5*3600000).toISOString().slice(0,16);
  leisureDialog.showModal();
});
$('leisure-close').addEventListener('click',()=>leisureDialog.close());
$('leisure-later').addEventListener('click',()=>returnDialog.close());
$('leisure-form').addEventListener('submit',async e=>{
  e.preventDefault();if(active()?.id!==leisureSessionId){leisureDialog.close();return;}
  const until=Date.parse($('leisure-until').value+':00+05:00');
  if(!Number.isSafeInteger(until)||until<=Date.now()||until>Date.now()+86400000){$('leisure-error').textContent='Выбери будущее время в пределах 24 часов.';return;}
  if(await action('leisure',{sessionId:leisureSessionId,leisureUntil:until}))leisureDialog.close();
  else $('leisure-error').textContent=$('message').textContent;
});
$('leisure-return').addEventListener('click',async()=>{
  if(active()?.id!==returnSessionId||!resting(active())){returnDialog.close();return;}
  if(await action('resume',{sessionId:returnSessionId}))returnDialog.close();
});
async function post(path, body) {
  const response = await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),cache:'no-store',signal:AbortSignal.timeout(10000)});
  const result = await response.json();
  if (!response.ok) { const error = new Error(result.error || 'Не удалось отправить запись.'); error.kind=result.kind; error.details=result.details; error.http=response.status; throw error; }
  return result;
}
async function refresh() { state=await store.read(); render(); }
function changed() { channel?.postMessage('changed'); }
function render() {
  $('connection').textContent=status;
  $('setup').hidden=Boolean(state?.context); $('ready').hidden=!state?.context;
  if (!state?.context) return;
  if (!formInitialized) {
    $('work-ref').innerHTML='<option value="">Отдельная активность</option>'+state.context.entities.map(e=>`<option value="${esc(e.ref)}">${esc(e.title)}</option>`).join('');
    $('metric').innerHTML='<option value="unclassified">Требует разбора</option><option value="outside">Вне нормативов</option>'+state.context.metrics.map(e=>`<option value="${esc(e.id)}">${esc(e.title)}</option>`).join('');
    for(const [id,key] of [['work-minutes','workMinutes'],['short-minutes','shortBreakMinutes'],['long-minutes','longBreakMinutes'],['cycle','longBreakEvery']]) $(id).value=state.timer.settings[key];
    formInitialized=true;
  }
  $('context-note').textContent='Список работ обновлён: '+stamp(state.context.capturedAt)+' · учёт по Ташкенту, UTC+5';
  $('server-active').hidden=!state.context.active;
  $('server-active').textContent=state.context.active?'На сервере был активен таймер «'+state.context.active.title+'» при последнем соединении. Здесь можно сохранить отдельный сеанс; пересечения потребуют разбора.':'';
  const s=active(); if($('finish-dialog').open&&s?.id!==finishSessionId){$('finish-dialog').close();finishSessionId=null;} $('active-card').hidden=!s; $('start-card').hidden=Boolean(s);ambience.update({active:s});if(!s)$('clock').textContent=duration(state.timer.settings.workMinutes*60000);
  if(s) { $('active-title').textContent=s.title; $('phase').textContent=s.phase==='work'?'РАБОТА · НА УСТРОЙСТВЕ':'ПЕРЕРЫВ · НА УСТРОЙСТВЕ'; $('pause').textContent=s.status==='paused'?'Продолжить':'Пауза'; $('extend').hidden=s.mode!=='pomodoro'; tick(); }
  if(leisureDialog.open&&s?.id!==leisureSessionId)leisureDialog.close();
  if(returnDialog.open&&(s?.id!==returnSessionId||!resting(s)))returnDialog.close();
  leisureButton.hidden=s?.phase!=='work';leisureButton.textContent=resting(s)?'Изменить Leisure':'Leisure';
  if(resting(s)){$('phase').textContent='LEISURE · НА УСТРОЙСТВЕ';$('pause').textContent='Вернуться к работе';}
  const records=Object.values(state.queue).reverse();
  const pending=records.filter(r=>r.status==='pending').length, conflicts=records.filter(r=>r.status==='conflict').length;
  $('counts').textContent=`К отправке: ${pending} · Разобрать: ${conflicts}`;
  $('records').innerHTML=records.map(r=>`<article class="record"><strong>${esc(r.session.title)}</strong><div class="record-meta"><span>${esc(stamp(r.session.startedAt))}</span><span>${duration(r.session.intervals.reduce((v,i)=>v+i.end-i.start,0))}</span><span>${r.session.phase!=='work'?'Перерыв · ':''}${r.status==='synced'?(r.receipt.status==='excluded'?'На сервере · без учёта времени':'На сервере'):r.status==='conflict'?'Нужен разбор':'Сохранено здесь · ждёт отправки'}</span></div>${r.session.observation?`<p class="note">${esc(r.session.observation)}</p>`:''}${r.error?`<p class="record-error">${esc(r.error)}${r.details?.length?' '+r.details.map(d=>esc(d.title)).join(', '):''}</p>`:''}${r.status==='conflict'?`<div class="toolbar"><button class="secondary" data-retry="${esc(r.session.id)}">Проверить снова</button><button class="secondary" data-exclude="${esc(r.session.id)}">Сохранить без учёта времени</button></div>`:''}</article>`).join('')||'<p class="note">No Data</p>';
  $('sync').disabled=syncing||readOnly;
  for(const b of $('active-card').querySelectorAll('button')) b.disabled=acting||readOnly;
}
function tick() {
  const s=active(); if(!s) return;
  const view=sessionView(s,Date.now()); $('clock').textContent=duration(resting(s)?view.leisureRemainingMs:s.mode==='pomodoro'?view.remainingMs:view.elapsedMs);
  $('active-note').textContent=s.status==='paused'?'Пауза · время не учитывается':view.expired?'Интервал завершён. Подтверди факт или продли на 5 минут.':'Сохранено на устройстве · можно закрыть страницу';
  if(resting(s)){
    $('active-note').textContent=`Leisure до ${stamp(s.leisure.until)} · работа на паузе · отдых ${(view.leisureMs/60000).toFixed(1)} мин`;
    const key=`${s.id}:${s.leisure.start}:${s.leisure.until}`;
    if(view.leisureRemainingMs===0&&!document.hidden&&!readOnly&&!acting&&!document.querySelector('dialog[open]')&&leisurePromptKey!==key){leisurePromptKey=key;returnSessionId=s.id;$('leisure-title').textContent=s.title;returnDialog.showModal();}
  }
  if(view.expired&&alarmId!==s.id) { alarmId=s.id; try { if(Notification.permission==='granted') new Notification('I&W · Интервал завершён',{body:s.title}); } catch {} }
  const key=s.id+':'+s.plannedMs;
  if(view.expired&&s.phase==='work'&&!document.hidden&&!readOnly&&!acting&&!$('finish-dialog').open&&reviewKey!==key){reviewKey=key;beginFinish();}
}
function beginFinish(){const s=active();if(!s||acting||readOnly)return;const view=sessionView(s,Date.now());if(finishSessionId!==s.id)$('observation').value='';finishSessionId=s.id;$('finish-dialog').querySelector('h2').textContent=s.mode==='pomodoro'&&s.phase==='work'?'Как прошла помидорка?':'Подтверди фактическое время';const workedMinutes=Number((Math.min(86400,Math.floor(view.elapsedMs/1000))/60).toFixed(2));$('worked-seconds').value=workedMinutes;$('worked-seconds').max=workedMinutes;$('finish-note').textContent='По отсчёту: '+new Intl.NumberFormat('ru-RU',{maximumFractionDigits:2}).format(workedMinutes)+' мин'+'. Паузы исключены. Можно уменьшить факт, если отвлёкся.';if(!$('finish-dialog').open)$('finish-dialog').showModal();$('observation').focus();}
async function action(name,input={}) {
  if(acting||readOnly) return; acting=true;
  try { state=await store.action(name,input,state.timer.revision); changed(); message(''); if(['finish','cancel'].includes(name)) void sync(); return true; }
  catch(e) { message(e.message); await refresh(); return false; }
  finally { acting=false; render(); }
}
async function connect() {
  if(readOnly) throw new Error('В этой версии доступен просмотр. Подключи рабочий сервер.');
  state??=await store.update(()=>{});
  const context=await post('/api/offline/connect',{deviceId:state.deviceId});
  if(state.context&&context.serverId!==state.context.serverId) throw new Error('Адрес ведёт к другому серверу. Локальные записи не отправлены. Выгрузи их и вернись к прежнему серверу.');
  state=await store.update(s=>{const first=!s.context; s.context=context; if(first) s.timer.settings=context.settings;});
  changed(); status='Сервер доступен'; render();
}
async function sync() {
  if(syncing||!state?.context||readOnly) return;
  syncing=true; render();
  try {
    state=await syncDevice(store); changed();
    status='Сервер доступен';
  } catch(e) { status='На устройстве · ждём сервер'; if(e.http||!['TimeoutError','TypeError','AbortError'].includes(e.name)) message(e.message); }
  finally { syncing=false; await refresh(); }
}
$('connect').addEventListener('click',async()=>{ $('connect').disabled=true; try { await connect(); const persisted=await navigator.storage?.persist?.(); $('storage-note').textContent=persisted?'Браузер выделил постоянное хранилище. Выгрузка поможет при смене телефона или очистке данных.':'Записи хранятся в браузере. Периодически сохраняй локальную выгрузку.'; if('serviceWorker' in navigator) await navigator.serviceWorker.ready; message('Устройство готово к работе без сети.'); } catch(e){message(e.message);} finally{$('connect').disabled=false;} });
$('sync').addEventListener('click',()=>void sync());
$('work-ref').addEventListener('change',()=>{ const e=state.context.entities.find(e=>e.ref===$('work-ref').value); if(e) $('title').value=e.title; });
const settings=()=>({workMinutes:Number($('work-minutes').value),shortBreakMinutes:Number($('short-minutes').value),longBreakMinutes:Number($('long-minutes').value),longBreakEvery:Number($('cycle').value)});
$('start-form').addEventListener('submit',async e=>{e.preventDefault(); const chosen=$('metric').value; await action('start',{title:$('title').value,workRef:$('work-ref').value||null,metricId:['outside','unclassified'].includes(chosen)?null:chosen,allocation:chosen,workType:$('work-type').value,mode:$('mode').value,settings:settings()}); if('Notification' in window&&Notification.permission==='default') void Notification.requestPermission().catch(()=>{});});
$('break').addEventListener('click',()=>void action('startBreak',{settings:settings()}));
$('pause').addEventListener('click',()=>void action(active().status==='paused'?'resume':'pause',{sessionId:active().id}));
$('extend').addEventListener('click',()=>{alarmId=null; void action('extend',{sessionId:active().id});});
$('finish').addEventListener('click',beginFinish);
$('finish-close').addEventListener('click',()=>$('finish-dialog').close());
$('finish-form').addEventListener('submit',async e=>{e.preventDefault(); const s=active(); if(!s||s.id!==finishSessionId){$('finish-dialog').close();message('Сеанс уже изменён в другом окне.');return;} await action('finish',{sessionId:s.id,workedSeconds:Math.round(Number($('worked-seconds').value)*60),observation:$('observation').value}); if(!active()) $('finish-dialog').close();});
$('cancel').addEventListener('click',()=>{if(confirm('Отменить? Сеанс сохранится в истории без выполнения норматива.')) void action('cancel',{sessionId:active().id});});
$('records').addEventListener('click',async e=>{const b=e.target.closest('[data-retry],[data-exclude]'); if(!b) return; const id=b.dataset.retry??b.dataset.exclude;
  if(b.dataset.exclude&&!confirm('Сохранить исходный сеанс на сервере без добавления часов? Локальная запись тоже останется.')) return;
  try {state=await store.update(s=>{const r=s.queue[id]; if(r.status==='synced') return; r.status='pending'; r.error=null; if(b.dataset.exclude) r.resolution='exclude';}); changed(); await sync();} catch(error){message(error.message);}
});
$('export').addEventListener('click',async()=>{try {const data=await store.read(), blob=new Blob([JSON.stringify({format:'indicators-work-device',version:1,exportedAt:new Date().toISOString(),data},null,2)+'\n'],{type:'application/json'}), url=URL.createObjectURL(blob), a=document.createElement('a'); a.href=url; a.download='indicators-work-device-'+new Date().toISOString().slice(0,10)+'.json'; a.click(); setTimeout(()=>URL.revokeObjectURL(url),1000);} catch(e){message(e.message);}});
channel?.addEventListener('message',()=>void refresh().catch(e=>message(e.message)));
window.addEventListener('online',()=>void sync()); document.addEventListener('visibilitychange',()=>{if(!document.hidden) void refresh().then(sync).catch(e=>message(e.message));});
setInterval(()=>{if(!document.hidden) tick();},250); setInterval(()=>{if(!document.hidden) void sync();},30000);
if('serviceWorker' in navigator&&window.isSecureContext) void navigator.serviceWorker.register('/service-worker.js').catch(e=>message('Не удалось подготовить открытие без сети: '+e.message));
try {await refresh(); if(state?.context) void sync(); else if(readOnly) message('Здесь доступен просмотр. Подключи рабочую версию на ПК для офлайн-учёта.');} catch(e){message('Локальное хранилище недоступно: '+e.message); $('connect').disabled=true;}
