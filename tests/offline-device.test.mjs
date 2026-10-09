import test from 'node:test';
import assert from 'node:assert/strict';
import { IDBFactory } from 'fake-indexeddb';
import { createDeviceStore } from '../public/offline-store.js';
import { syncDevice } from '../public/offline-engine.js';
import { sessionView } from '../public/timer-core.js';
const now=Date.parse('2026-10-09T10:00:00+05:00');
const context={serverId:crypto.randomUUID(),metrics:[{id:'guides',title:'Руководства',unit:'hours'}],entities:[],settings:{workMinutes:25,shortBreakMinutes:5,longBreakMinutes:15,longBreakEvery:4}};
const start={title:'Работа офлайн',mode:'pomodoro',metricId:'guides',workRef:null,allocation:'assigned'};
async function fixture(){const factory=new IDBFactory(),store=createDeviceStore(factory);await store.update(s=>{s.context=context;});return {factory,store};}
test('IndexedDB восстанавливает активный сеанс после закрытия; очередь записывается вместе с завершением',async()=>{
  const {store,factory}=await fixture(); await store.action('start',start,0,now); await store.close();
  const reopened=createDeviceStore(factory),state=await reopened.read(); assert.equal(sessionView(state.timer.sessions[0],now+60000).remainingMs,1440000);
  const result=await reopened.action('finish',{sessionId:state.timer.activeId},1,now+60000);
  assert.equal(result.timer.activeId,null); const r=Object.values(result.queue)[0]; assert.equal(r.status,'pending'); assert.equal(r.session.intervals[0].end-r.session.intervals[0].start,60000); await reopened.close();
});
test('Две вкладки не запускают два сеанса; устаревшее действие не меняет запись',async()=>{
  const {store,factory}=await fixture(),other=createDeviceStore(factory);
  const results=await Promise.allSettled([store.action('start',start,0,now),other.action('start',start,0,now)]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1); assert.equal((await store.read()).timer.sessions.length,1); await store.close(); await other.close();
});
test('Настройки устройства переживают перезапуск; неполная помидорка не считается полной',async()=>{
  const {store,factory}=await fixture(); const started=await store.action('start',{...start,settings:{workMinutes:15,shortBreakMinutes:3,longBreakMinutes:12,longBreakEvery:3}},0,now);
  const ended=await store.action('finish',{sessionId:started.timer.activeId},1,now+60000); assert.equal(Object.values(ended.queue)[0].session.completedPomodoros,0);
  await store.close(); const reopened=createDeviceStore(factory),saved=await reopened.read(); assert.equal(saved.timer.settings.workMinutes,15); assert.equal(saved.timer.settings.shortBreakMinutes,3); await reopened.close();
});
test('Потеря ответа после учёта: очередь остаётся и повтор получает квитанцию; исходник не удаляется',async()=>{
  const {store}=await fixture(); const started=await store.action('start',start,0,now); await store.action('finish',{sessionId:started.timer.activeId},1,now+60000);
  let calls=0; const receipts=new Map();
  const post=async(route,payload)=>{if(route.endsWith('connect'))return context;calls++;const id=payload.session.id;let receipt=receipts.get(id);if(!receipt){receipt={sessionId:id,status:'accepted',entryIds:['fact']};receipts.set(id,receipt);throw new TypeError('network lost');}return {duplicate:true,receipt};};
  await assert.rejects(()=>syncDevice(store,post),/network lost/); assert.equal(Object.values((await store.read()).queue)[0].status,'pending');
  await syncDevice(store,post); assert.equal(calls,2); assert.equal(receipts.size,1); const record=Object.values((await store.read()).queue)[0]; assert.equal(record.status,'synced'); assert.equal(record.session.title,'Работа офлайн'); await store.close();
});
test('Конфликт остаётся для разбора; смена сервера не отправляет данные; часы назад не дают отрицательный факт',async()=>{
  const {store}=await fixture(); const s=await store.action('start',start,0,now); await assert.rejects(()=>store.action('pause',{sessionId:s.timer.activeId},1,now-1000),/назад/);
  await store.action('finish',{sessionId:s.timer.activeId},1,now+60000); let imports=0;
  await assert.rejects(()=>syncDevice(store,async()=>({...context,serverId:crypto.randomUUID()})),/другому серверу/); assert.equal(imports,0);
  await syncDevice(store,async route=>{if(route.endsWith('connect'))return context; imports++; const e=new Error('Пересечение');e.http=409;e.kind='offline_overlap';throw e;});
  const q=Object.values((await store.read()).queue)[0]; assert.equal(q.status,'conflict'); assert.equal(q.session.status,'finished'); assert.equal(imports,1); await store.close();
});
