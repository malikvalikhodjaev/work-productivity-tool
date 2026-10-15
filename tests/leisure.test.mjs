import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {createStore} from '../lib/store.mjs';

const week='2026-10-12';
function fixture(){
  let time=Date.parse('2026-10-15T10:00:00+05:00');
  const file=path.join(mkdtempSync(path.join(tmpdir(),'iw-leisure-')),'dashboard.json');
  const options={now:()=>time,validateWorkRef:ref=>ref??null,getEntities:()=>[{ref:'work:one',title:'Работа'}]};
  let store=createStore(file,options);
  const command=(action,input={})=>({action,input:{requestId:randomUUID(),expectedRevision:store.getTimer(week).revision,week,...input}});
  const send=c=>store.mutateTimer(c.action,c.input);
  const act=(a,i)=>send(command(a,i));
  return {get store(){return store;},file,command,send,act,get now(){return time;},advance:ms=>time+=ms,
    reopen:()=>store=createStore(file,options),
    start:()=>act('start',{title:'Работа',mode:'pomodoro',metricId:'guides',allocation:'assigned',workRef:'work:one'}).active};
}

test('Leisure сохраняет общий сеанс; срок только предлагает возврат и не добавляет работу',()=>{
  const f=fixture(),s=f.start();f.advance(600000);
  f.act('leisure',{sessionId:s.id,leisureUntil:f.now+900000});
  f.advance(1200000);f.reopen();
  const paused=f.store.getTimer(week);
  assert.equal(paused.active.status,'paused');assert.equal(paused.active.id,s.id);
  assert.equal(paused.active.elapsedMs,600000);assert.equal(paused.active.leisureRemainingMs,0);
  assert.equal(paused.summary.leisureSeconds,1200);assert.equal(f.store.getStoredEntries().entries.length,0);
  f.act('resume',{sessionId:s.id});f.advance(900000);f.act('finish',{sessionId:s.id});
  const result=f.store.getTimer(week);
  assert.equal(result.summary.workSeconds,1500);assert.equal(result.summary.leisureSeconds,1200);
  assert.equal(result.summary.pomodoros,1);assert.equal(result.sessions[0].leisureIntervals.length,1);
});

test('Потерянный ответ Leisure повторяет исходный ID без второго отдыха',()=>{
  const f=fixture(),s=f.start();f.advance(60000);
  const command=f.command('leisure',{sessionId:s.id,leisureUntil:f.now+60000});
  const first=f.send(command);const raw=readFileSync(f.file,'utf8');f.advance(120000);
  const repeated=f.send(command);
  assert.equal(repeated.duplicate,true);assert.deepEqual(repeated.active.leisure,first.active.leisure);
  assert.equal(readFileSync(f.file,'utf8'),raw);assert.equal(repeated.active.status,'paused');
});

test('Неверный срок и истёкшая помидорка не меняют исходный сеанс',()=>{
  const f=fixture(),s=f.start();const raw=readFileSync(f.file,'utf8');
  for(const until of [f.now,f.now-1,f.now+86400001,'21:00']){
    assert.throws(()=>f.act('leisure',{sessionId:s.id,leisureUntil:until}),/24 часа/);
    assert.equal(readFileSync(f.file,'utf8'),raw);
  }
  f.advance(1500000);
  assert.throws(()=>f.act('leisure',{sessionId:s.id,leisureUntil:f.now+60000}),/истёкшую/);
  assert.equal(readFileSync(f.file,'utf8'),raw);
});

test('Изменение срока сохраняет начало Leisure; досрочный возврат завершает один интервал',()=>{
  const f=fixture(),s=f.start();f.advance(300000);const start=f.now;
  f.act('leisure',{sessionId:s.id,leisureUntil:f.now+900000});f.advance(120000);
  f.act('leisure',{sessionId:s.id,leisureUntil:f.now+1800000});f.advance(180000);
  const r=f.act('resume',{sessionId:s.id}).active;
  assert.equal(r.leisure,null);assert.deepEqual(r.leisureIntervals,[{start,end:f.now,plannedUntil:f.now+1620000}]);
  assert.equal(r.id,s.id);assert.equal(r.elapsedMs,300000);
});

test('Завершение во время Leisure и офлайн-импорт сохраняют отдых отдельно без дублей',()=>{
  const source=fixture(),s=source.start();source.advance(300000);
  source.act('leisure',{sessionId:s.id,leisureUntil:source.now+900000});source.advance(600000);
  source.act('finish',{sessionId:s.id,observation:'Отдых записан отдельно'});
  const raw=JSON.parse(readFileSync(source.file,'utf8')).timer.sessions[0];
  assert.equal(source.store.getTimer(week).summary.workSeconds,300);
  assert.equal(raw.completedPomodoros,0);
  const target=fixture();target.advance(900000);
  const deviceId=randomUUID(),serverId=target.store.offlineContext(deviceId).serverId;
  const packet={deviceId,serverId,session:raw};
  target.store.syncOffline(packet);assert.equal(target.store.syncOffline(packet).duplicate,true);
  assert.equal(target.store.getStoredEntries().entries.length,1);
  assert.equal(target.store.getTimer(week).summary.leisureSeconds,600);
  const imported=JSON.parse(readFileSync(target.file,'utf8')).timer.sessions[0];
  assert.deepEqual(imported.leisureIntervals,raw.leisureIntervals);assert.deepEqual(imported.offlineOriginal,raw);
});
