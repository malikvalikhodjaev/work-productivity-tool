import { createDeviceStore } from './offline-store.js';
import { syncDevice } from './offline-engine.js';
const store=createDeviceStore(), readOnly=document.querySelector('meta[name="dashboard-access"]')?.content==='viewer';
let busy=false;
async function refresh(sync=false) {
  if(busy||readOnly) return; busy=true;
  try {
    let state=await store.read();
    if(state?.context&&sync) { try {state=await syncDevice(store); window.dispatchEvent(new Event('rhythm:entry-classified'));} catch{} }
    const badge=document.getElementById('device-timer-badge');
    if(badge&&state?.context) {const q=Object.values(state.queue), pending=q.filter(r=>r.status==='pending').length, conflicts=q.filter(r=>r.status==='conflict').length;
      badge.textContent=state.timer.activeId?'На устройстве идёт сеанс':conflicts?`Разобрать: ${conflicts}`:pending?`Ждут отправки: ${pending}`:'Работает без сети';}
  } catch{} finally {busy=false;}
}
if('BroadcastChannel' in window) new BroadcastChannel('indicators-work-device').addEventListener('message',()=>void refresh(true));
window.addEventListener('online',()=>void refresh(true)); document.addEventListener('visibilitychange',()=>{if(!document.hidden) void refresh(true);});
setInterval(()=>{if(!document.hidden) void refresh(true);},30000); void refresh(true);
