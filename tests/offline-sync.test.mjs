import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { createStore, metrics } from '../lib/store.mjs';
import { replaceFile } from '../lib/atomic-file.mjs';
import { changeTimer } from '../lib/timer.mjs';
const at=Date.parse('2026-10-09T10:00:00+05:00'), week='2026-10-05';
function session({start=at,duration=1500,extra={}}={}) {
  const context={now:start,metrics,validateWorkRef:ref=>ref};
  const first=changeTimer(undefined,'start',{requestId:randomUUID(),expectedRevision:0,title:'模型 · чтение',mode:'pomodoro',metricId:'guides',allocation:'assigned',workRef:'task:real',workType:'Создание',...extra},context);
  return changeTimer(first.timer,'finish',{requestId:randomUUID(),expectedRevision:1,sessionId:first.timer.activeId},{...context,now:start+duration*1000}).timer.sessions[0];
}
function fixture() {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'iw-offline-')),file=path.join(dir,'dashboard.json'); let clock=at+3600000, fail=false;
  const options={now:()=>clock,getEntities:()=>[{ref:'task:real',title:'Работа'}],validateWorkRef:ref=>{if(ref&&ref!=='task:real') throw new Error('missing');return ref??null;},storage:{...fs,replaceFile,writeFileSync:(...args)=>{if(fail) throw new Error('disk full');fs.writeFileSync(...args);}}};
  let store=createStore(file,options); const deviceId=randomUUID(),context=store.offlineContext(deviceId);
  const payload=s=>({deviceId,serverId:context.serverId,session:s});
  return {file,payload,context,deviceId,get store(){return store;},reopen:()=>{store=createStore(file,options);},setClock:ms=>{clock=ms;},fail:value=>{fail=value;}};
}
test('Офлайн-факт и квитанция атомарны; повтор после перезапуска не удваивает норматив',()=>{
  const f=fixture(),p=f.payload(session()); const result=f.store.syncOffline(p); assert.equal(result.receipt.status,'accepted'); f.reopen();
  assert.equal(f.store.syncOffline(p).duplicate,true); assert.equal(f.store.getStoredEntries().entries.length,1);
  assert.equal(f.store.getTimer(week).summary.workSeconds,1500); assert.equal(f.store.getTimer(week).summary.pomodoros,1);
  assert.equal(f.store.getWeek(week).metrics.find(m=>m.id==='guides').percent,4);
  assert.throws(()=>f.store.syncOffline({...p,session:{...p.session,title:'Изменено'}}),e=>e.kind==='offline_changed');
});
test('Сбой записи не сохраняет частичную квитанцию; повтор сохраняет факт целиком',()=>{
  const f=fixture(),p=f.payload(session()),raw=fs.readFileSync(f.file,'utf8'); f.fail(true);
  assert.throws(()=>f.store.syncOffline(p),/disk full/); assert.equal(fs.readFileSync(f.file,'utf8'),raw); assert.equal(f.store.getStoredEntries().entries.length,0);
  f.fail(false); assert.equal(f.store.syncOffline(p).duplicate,false); assert.equal(f.store.getStoredEntries().entries.length,1);
});
test('Пересекающийся серверный таймер требует разбора; исключение хранит исходник без часов',()=>{
  const f=fixture(),s=session(), p=f.payload(s); f.setClock(at);
  f.store.mutateTimer('start',{requestId:randomUUID(),expectedRevision:0,title:'На ПК',mode:'pomodoro',metricId:'reading',workRef:'task:real'}); f.setClock(at+1800000);
  const raw=fs.readFileSync(f.file,'utf8'); assert.throws(()=>f.store.syncOffline(p),e=>e.kind==='offline_overlap'&&e.details.length===1); assert.equal(fs.readFileSync(f.file,'utf8'),raw);
  const result=f.store.syncOffline({...p,resolution:'exclude'}); assert.equal(result.receipt.status,'excluded'); assert.equal(f.store.getStoredEntries().entries.length,0);
  const saved=JSON.parse(fs.readFileSync(f.file,'utf8')).timer.sessions.find(v=>v.id===s.id); assert.deepEqual(saved.offlineOriginal,s); assert.equal(saved.status,'cancelled'); assert.equal(f.store.getTimer(week).active.title,'На ПК');
});
test('Непересекающаяся запись не заменяет активный сеанс; пауза не считается пересечением',()=>{
  const f=fixture(); f.setClock(at); const active=f.store.mutateTimer('start',{requestId:randomUUID(),expectedRevision:0,title:'На ПК',mode:'stopwatch',metricId:'reading',workRef:'task:real'}).active;
  f.setClock(at+60000); f.store.mutateTimer('pause',{requestId:randomUUID(),expectedRevision:1,sessionId:active.id});
  f.setClock(at+3600000); assert.equal(f.store.syncOffline(f.payload(session({start:at+120000,duration:60}))).receipt.status,'accepted');
  assert.equal(f.store.getTimer(week).active.id,active.id); assert.equal(f.store.getTimer(week).summary.workSeconds,60);
});
test('Смена недели, секунды и перерывы: только рабочие интервалы выполняют норму',()=>{
  const f=fixture(),start=Date.parse('2026-10-11T23:59:30+05:00'); f.setClock(start+3600000);
  const s=session({start,duration:60}); f.store.syncOffline(f.payload(s));
  assert.deepEqual(f.store.getStoredEntries().entries.map(e=>[e.date,e.durationSeconds]),[['2026-10-11',30],['2026-10-12',30]]);
  const rest={...session({start:start+120000,duration:60}),phase:'short_break',metricId:null,workRef:null,allocation:'break'}; f.store.syncOffline(f.payload(rest));
  assert.equal(f.store.getStoredEntries().entries.length,2);
});
test('Другой сервер, неизвестная работа, будущее время и повреждённые интервалы оставляют файл без изменений',()=>{
  const f=fixture(),s=session(),raw=fs.readFileSync(f.file,'utf8');
  assert.throws(()=>f.store.syncOffline({...f.payload(s),serverId:randomUUID()}),e=>e.kind==='offline_server');
  assert.throws(()=>f.store.syncOffline(f.payload({...s,workRef:'task:gone'})),e=>e.kind==='offline_reference');
  for(const changed of [{...s,finishedAt:'2099-01-01T00:00:00Z'},{...s,intervals:[{start:at+1000,end:at}]}]) assert.throws(()=>f.store.syncOffline(f.payload(changed)));
  assert.equal(fs.readFileSync(f.file,'utf8'),raw);
});
test('Отмена забытого секундомера дольше суток сохраняет историю без рабочего факта',()=>{
  const f=fixture(),context={now:at,metrics,validateWorkRef:ref=>ref};
  const first=changeTimer(undefined,'start',{requestId:randomUUID(),expectedRevision:0,title:'Забытый сеанс',mode:'stopwatch',metricId:null,allocation:'unclassified',workRef:null},context);
  const cancelled=changeTimer(first.timer,'cancel',{requestId:randomUUID(),expectedRevision:1,sessionId:first.timer.activeId},{...context,now:at+172800000}).timer.sessions[0];
  f.setClock(at+172800000); assert.equal(f.store.syncOffline(f.payload(cancelled)).receipt.status,'accepted'); assert.equal(f.store.getStoredEntries().entries.length,0);
});
