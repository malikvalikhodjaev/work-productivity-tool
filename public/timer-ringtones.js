export const timerRingtones = Object.freeze([
  {id:'bip_bip',title:'Бип-бип',description:'Две пары коротких мягких импульсов'},
  {id:'sonar',title:'Сонар',description:'Три округлых сигнала с паузами'},
  {id:'glass',title:'Стекло',description:'Светлый звон из трёх нот'},
  {id:'marimba',title:'Маримба',description:'Четыре тёплые деревянные ноты'},
  {id:'orbit',title:'Орбита',description:'Спокойный восходящий и ответный мотив'},
  {id:'warm_bell',title:'Тёплый колокол',description:'Два мягких удара с затуханием'},
  {id:'classic',title:'Прежний сигнал',description:'Короткий однотонный сигнал'}
]);
const key='iw-timer-ringtone-v1';
export function ringtonePreferences(value) {
  return {id:timerRingtones.some(r=>r.id===value?.id)?value.id:'bip_bip',
    volume:typeof value?.volume==='number'&&Number.isFinite(value.volume)?Math.max(0,Math.min(1,value.volume)):.65};
}
export function readRingtonePreferences(){try{return ringtonePreferences(JSON.parse(localStorage.getItem(key)));}catch{return ringtonePreferences();}}
let player;
const listeners=new Set();
export function stopTimerRingtone(){if(player){player.pause();player.currentTime=0;player=null;}}
export async function playTimerRingtone(preferences=readRingtonePreferences()) {
  const choice=ringtonePreferences(preferences);stopTimerRingtone();
  const audio=new Audio(`/ringtones/${choice.id}.wav`);player=audio;audio.loop=false;audio.volume=choice.volume;
  try{await audio.play();for(const notify of listeners)notify('');}
  catch(error){if(player===audio)for(const notify of listeners)notify('Нажми «Прослушать», чтобы браузер разрешил звук.');throw error;}
}
export function mountTimerRingtones(host){
  if(!document.querySelector('link[data-timer-ringtones]')){const css=document.createElement('link');css.rel='stylesheet';css.href='/timer-ringtones.css';css.dataset.timerRingtones='';document.head.append(css);}
  const box=document.createElement('details');box.className='timer-ringtones';box.dataset.localControl='';
  const summary=document.createElement('summary');summary.textContent='Сигнал таймера';box.append(summary);
  const description=document.createElement('p');description.className='timer-note';box.append(description);
  const label=document.createElement('label');label.textContent='Мелодия';
  const select=document.createElement('select');select.setAttribute('aria-label','Мелодия таймера');
  for(const r of timerRingtones){const option=document.createElement('option');option.value=r.id;option.textContent=r.title;select.append(option);}label.append(select);box.append(label);
  const controls=document.createElement('div');controls.className='timer-ringtone-actions';
  const preview=document.createElement('button');preview.type='button';preview.className='button secondary';preview.textContent='▶ Прослушать';
  const stop=document.createElement('button');stop.type='button';stop.className='button secondary';stop.textContent='Стоп';controls.append(preview,stop);box.append(controls);
  const volumeLabel=document.createElement('label');volumeLabel.textContent='Громкость сигнала';
  const volume=document.createElement('input');volume.type='range';volume.min='0';volume.max='100';volume.step='5';volume.setAttribute('aria-label','Громкость сигнала таймера');volumeLabel.append(volume);box.append(volumeLabel);
  const status=document.createElement('p');status.className='timer-note';status.setAttribute('role','status');box.append(status);
  const hint=document.createElement('p');hint.className='timer-note';hint.textContent='Выбор сохраняется в этом браузере. Сигнал звучит один раз; громкость отдельна от фонового звука. Для звука страница должна быть открыта.';box.append(hint);
  const paint=()=>{const prefs=readRingtonePreferences();select.value=prefs.id;volume.value=String(prefs.volume*100);const r=timerRingtones.find(r=>r.id===prefs.id);summary.textContent='Сигнал таймера · '+r.title;description.textContent=r.description;};
  const save=()=>{const prefs=ringtonePreferences({id:select.value,volume:Number(volume.value)/100});try{localStorage.setItem(key,JSON.stringify(prefs));status.textContent='Выбор сохранён';}catch{status.textContent='Не удалось сохранить выбор в браузере.';}paint();};
  select.onchange=()=>{stopTimerRingtone();save();};volume.oninput=save;
  preview.onclick=async()=>{const id=select.value;try{await playTimerRingtone({id,volume:Number(volume.value)/100});status.textContent='Прослушивание: '+timerRingtones.find(r=>r.id===id).title;}catch{}};
  stop.onclick=()=>{stopTimerRingtone();status.textContent='Прослушивание остановлено';};
  listeners.add(message=>{status.textContent=message;});window.addEventListener('pagehide',stopTimerRingtone);
  paint();const ambience=host.querySelector('.focus-ambience');if(ambience)ambience.after(box);else host.append(box);return box;
}
