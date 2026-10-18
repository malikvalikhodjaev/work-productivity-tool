import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {IDBFactory} from 'fake-indexeddb';
import {createStore} from '../lib/store.mjs';
import {createDeviceStore} from '../public/offline-store.js';

const at=Date.parse('2026-10-13T09:00:00+05:00'),week='2026-10-12';
const start={title:'Работа с моделью',mode:'pomodoro',metricId:'guides',allocation:'assigned',workRef:null};
function fixture(){const file=path.join(mkdtempSync(path.join(tmpdir(),'iw-review-')),'dashboard.json');let clock=at;const options={now:()=>clock};let store=createStore(file,options);return {file,get store(){return store;},advance:seconds=>{clock+=seconds*1000;},reopen:()=>{store=createStore(file,options);},act:(action,input={})=>store.mutateTimer(action,{...input,week,expectedRevision:store.getTimer(week).revision,requestId:randomUUID()})};}

test('Наблюдение сохраняется с фактом атомарно, переживает перезапуск и повтор не удваивает время',()=>{
  const f=fixture(),s=f.act('start',start).active;f.advance(1500);
  const observation='  模型 · понял критерий\nЗавтра проверить «клиента»\n  ';
  const payload={sessionId:s.id,observation,workedSeconds:1500,week,expectedRevision:1,requestId:randomUUID()};
  f.store.mutateTimer('finish',payload);f.reopen();
  assert.equal(f.store.getTimer(week).sessions[0].observation,observation);
  assert.equal(f.store.mutateTimer('finish',payload).duplicate,true);
  assert.equal(f.store.getStoredEntries().entries.length,1);
  assert.equal(f.store.getTimer(week).summary.workSeconds,1500);
  assert.throws(()=>f.store.mutateTimer('finish',{...payload,observation:'Иное'}),e=>e.status===409);
});

test('Некорректное наблюдение не завершает сеанс, не создаёт факт и не меняет файл',()=>{
  const f=fixture(),s=f.act('start',start).active;f.advance(60);const raw=readFileSync(f.file,'utf8');
  for(const observation of ['x'.repeat(10001),{text:'Ошибка'}])assert.throws(()=>f.act('finish',{sessionId:s.id,observation}),/10000 символов/);
  assert.equal(readFileSync(f.file,'utf8'),raw);assert.equal(f.store.getTimer(week).active.id,s.id);
  assert.equal(f.store.getStoredEntries().entries.length,0);
});

test('Старые сеансы без наблюдения читаются без выдуманной заметки; пустой ответ допустим',()=>{
  const f=fixture(),s=f.act('start',start).active;f.advance(30);f.act('finish',{sessionId:s.id});f.reopen();
  assert.equal(f.store.getTimer(week).sessions[0].observation,undefined);
  const second=f.act('start',start).active;f.advance(20);f.act('finish',{sessionId:second.id,observation:''});
  assert.equal(f.store.getTimer(week).sessions[0].observation,'');assert.equal(f.store.getStoredEntries().entries.length,2);
});

test('Наблюдение устройства восстанавливается из очереди и отправляется с сеансом и квитанцией',async()=>{
  const f=fixture(),factory=new IDBFactory(),device=createDeviceStore(factory);const initialized=await device.update(()=>{});
  const context=f.store.offlineContext(initialized.deviceId);await device.update(state=>{state.context=context;});
  const started=await device.action('start',start,0,at);
  await device.action('finish',{sessionId:started.timer.activeId,observation:'  Отвлёкся\nОтключить чат  '},1,at+1500000);
  await device.close();const reopened=createDeviceStore(factory),state=await reopened.read(),record=Object.values(state.queue)[0];
  assert.equal(record.session.observation,'  Отвлёкся\nОтключить чат  ');f.advance(1800);
  const payload={deviceId:state.deviceId,serverId:context.serverId,session:record.session};
  assert.equal(f.store.syncOffline(payload).receipt.status,'accepted');f.reopen();
  assert.equal(f.store.getTimer(week).sessions[0].observation,record.session.observation);
  assert.equal(f.store.syncOffline(payload).duplicate,true);assert.equal(f.store.getStoredEntries().entries.length,1);
  assert.throws(()=>f.store.syncOffline({...payload,session:{...record.session,id:randomUUID(),observation:'x'.repeat(10001)}}),/10000 символов/);
  await reopened.close();
});
