import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { createStore } from '../lib/store.mjs';
import { replaceFile } from '../lib/atomic-file.mjs';
import { timerState } from '../lib/timer.mjs';
import { backupData } from '../lib/backup.mjs';
const week = '2026-10-05';
function fixture(start='2026-10-09T09:00:00+05:00') {
  const file=path.join(mkdtempSync(path.join(tmpdir(),'iw-timer-')),'dashboard.json'); let clock=Date.parse(start);
  const options={ now:()=>clock, validateWorkRef:ref=>{ if(ref && ref!=='task:real') throw new Error('No work'); return ref||null; }, getEntities:()=>[{ref:'task:real',title:'Реальная работа'}] };
  let store=createStore(file,options);
  const act=(action,input={})=>store.mutateTimer(action,{...input,week,requestId:randomUUID(),expectedRevision:store.getTimer(week).revision});
  return {file,options,act, get store(){return store;}, advance:seconds=>{clock+=seconds*1000;}, reopen:()=>{store=createStore(file,options);}, start:(extra={})=>act('start',{title:'Работа',mode:'pomodoro',metricId:'guides',allocation:'assigned',workRef:'task:real',workType:'Создание',...extra}).active };
}
test('Паузы и перерывы исключаются; факт переживает перезапуск и обновляет два разреза без удвоения',()=>{
  const f=fixture(), s=f.start(); f.advance(600); f.act('pause',{sessionId:s.id}); f.advance(900); f.reopen();
  assert.equal(f.store.getTimer(week).active.elapsedMs,600000); f.act('resume',{sessionId:s.id}); f.advance(900);
  f.act('finish',{sessionId:s.id}); f.act('workTarget',{workRef:'task:real',hours:1});
  assert.equal(f.store.getTimer(week).summary.workSeconds,1500); assert.equal(f.store.getTimer(week).summary.pomodoros,1);
  assert.equal(f.store.getTimer(week).plans[0].percent,42); assert.equal(f.store.getWeek(week).metrics.find(m=>m.id==='guides').percent,4);
  const rest=f.act('startBreak').active; f.advance(300); f.act('finish',{sessionId:rest.id}); f.reopen();
  assert.equal(f.store.getTimer(week).summary.breakSeconds,300); assert.equal(f.store.getTimer(week).summary.workSeconds,1500);
  assert.equal(f.store.getStoredEntries().entries.length,1); assert.equal(f.store.getStoredEntries().entries[0].durationSeconds,1500);
});
test('Один активный сеанс для двух клиентов; повтор завершения не удваивает время',()=>{
  const f=fixture(), raw=readFileSync(f.file,'utf8');
  assert.throws(()=>f.store.mutateTimer('start',{week:'bad-week',requestId:randomUUID(),expectedRevision:0,title:'Работа',mode:'pomodoro',metricId:'guides',workRef:'task:real'}),/корректную дату/);
  assert.equal(readFileSync(f.file,'utf8'),raw);
  const s=f.start(); assert.throws(()=>f.start(),error=>error.status===409); f.advance(1500);
  const input={week,sessionId:s.id,expectedRevision:1,requestId:randomUUID()};
  const result=f.store.mutateTimer('finish',input); assert.equal(result.duplicate,false);
  assert.equal(f.store.mutateTimer('finish',input).duplicate,true); assert.equal(f.store.getStoredEntries().entries.length,1);
  assert.throws(()=>f.store.mutateTimer('settings',{settings:result.settings,expectedRevision:1,requestId:randomUUID()}),error=>error.status===409);
  assert.throws(()=>f.store.mutateTimer('cancel',input),error=>error.status===409);
});
test('Закрытая страница и остановленный сервер не продлевают помидорку; добавление пяти минут не приписывает забытый час',()=>{
  const f=fixture(),s=f.start(); f.advance(7200); f.reopen(); assert.equal(f.store.getTimer(week).active.elapsedMs,1500000);
  assert.equal(f.store.getTimer(week).active.needsConfirmation,true); f.act('extend',{sessionId:s.id}); f.advance(300); f.act('finish',{sessionId:s.id});
  assert.equal(f.store.getStoredEntries().entries[0].durationSeconds,1800);
});
test('Неполный интервал сохраняет секунды; отмена остаётся в истории и не даёт факт',()=>{
  const f=fixture(),s=f.start(); f.advance(37); f.act('finish',{sessionId:s.id});
  assert.equal(f.store.getTimer(week).summary.workSeconds,37); assert.equal(f.store.getTimer(week).summary.pomodoros,0);
  const next=f.start(); f.advance(120); f.act('cancel',{sessionId:next.id}); assert.equal(f.store.getStoredEntries().entries.length,1);
  assert.equal(f.store.getTimer(week).sessions[0].status,'cancelled');
});
test('Разные пресеты дают 80 минут и 3 помидорки; ручная запись входит в норматив работы один раз',()=>{
  const f=fixture();
  for (const workMinutes of [15,15,50]) {
    const s=f.start({settings:{workMinutes,shortBreakMinutes:5,longBreakMinutes:15,longBreakEvery:4}});
    f.advance(workMinutes*60); f.act('finish',{sessionId:s.id});
  }
  f.store.addEntry({date:'2026-10-09',amount:0.5,title:'Ручной факт',metricId:'guides',workRef:'task:real'});
  f.act('workTarget',{workRef:'task:real',hours:2});
  const v=f.store.getTimer(week); assert.equal(v.summary.workSeconds,4800); assert.equal(v.summary.pomodoros,3); assert.equal(v.plans[0].percent,92);
  assert.ok(Math.abs(v.plans[0].actual-(80/60+0.5))<0.00001);
});
test('Секундомер после суток допускает уточнение; категории можно разобрать, сохраняя исходное время',()=>{
  const f=fixture(),s=f.start({mode:'stopwatch',metricId:null,allocation:'unclassified'}); f.advance(90000);
  assert.throws(()=>f.act('finish',{sessionId:s.id}),/Длинный/); f.act('finish',{sessionId:s.id,workedSeconds:3600});
  const e=f.store.getStoredEntries().entries[0]; f.store.classifyEntry(e.id,{metricId:'reading',workRef:'task:real',workType:'Обучение'});
  assert.equal(f.store.getTimer(week).summary.workSeconds,3600); assert.equal(f.store.getWeek(week).metrics.find(m=>m.id==='reading').percent,10);
  assert.equal(f.store.getStoredEntries().entries[0].classificationHistory.length,1); assert.throws(()=>f.store.removeEntry(e.id),/таймером/);
});
test('Полночь и смена недели: время распределяется по рабочим интервалам в Ташкенте',()=>{
  const f=fixture('2026-10-11T23:50:00+05:00'),s=f.start(); f.advance(1500); f.act('finish',{sessionId:s.id});
  const e=f.store.getStoredEntries().entries; assert.deepEqual(e.map(e=>[e.date,e.durationSeconds]),[['2026-10-11',600],['2026-10-12',900]]);
  assert.equal(f.store.getTimer(week).summary.workSeconds,600); assert.equal(f.store.getTimer('2026-10-12').summary.workSeconds,900);
});
test('Настройки сохраняются, активный план остаётся прежним; длинный перерыв завершает цикл',()=>{
  const f=fixture(); f.act('settings',{settings:{workMinutes:1,shortBreakMinutes:1,longBreakMinutes:2,longBreakEvery:2}});
  for(let i=0;i<2;i++){const s=f.start(); f.advance(60); f.act('finish',{sessionId:s.id});}
  const rest=f.act('startBreak').active; assert.equal(rest.phase,'long_break');
  f.act('settings',{settings:{workMinutes:50,shortBreakMinutes:10,longBreakMinutes:30,longBreakEvery:4}});
  assert.equal(f.store.getTimer(week).active.plannedMs,120000); f.advance(120); f.act('finish',{sessionId:rest.id}); f.reopen();
  assert.equal(f.store.getTimer(week).cycleCount,0); assert.equal(f.store.getTimer(week).settings.workMinutes,50);
});
test('Ошибка замены файла не завершает сеанс в памяти и не пишет отдельно запись времени',()=>{
  const f=fixture(),s=f.start(); f.advance(1500); const original=readFileSync(f.file,'utf8');
  const store=createStore(f.file,{...f.options,storage:{existsSync,mkdirSync,copyFileSync,readFileSync,writeFileSync,replaceFile:()=>{throw new Error('Disk failure');}}});
  assert.throws(()=>store.mutateTimer('finish',{sessionId:s.id,week,expectedRevision:1,requestId:randomUUID()}),/Disk failure/);
  assert.equal(readFileSync(f.file,'utf8'),original); assert.equal(store.getTimer(week).active.id,s.id); assert.equal(store.getStoredEntries().entries.length,0);
});
test('Повреждённое хранилище не заменяется; резервная копия сохраняет исходные байты и восстанавливается',()=>{
  const f=fixture(),root=path.dirname(f.file); f.start(); const bytes=readFileSync(f.file);
  mkdirSync(path.join(root,'imports','nested'),{recursive:true}); writeFileSync(path.join(root,'imports','nested','raw.csv'),'中文,тест\r\n');
  const result=backupData(root); assert.equal(backupData(root).unchanged,true);
  assert.deepEqual(readFileSync(path.join(root,'backups',result.directory,'dashboard.json')),bytes);
  assert.equal(readFileSync(path.join(root,'backups',result.directory,'imports','nested','raw.csv'),'utf8'),'中文,тест\r\n');
  const restored=path.join(mkdtempSync(path.join(tmpdir(),'iw-restore-')),'dashboard.json'); copyFileSync(path.join(root,'backups',result.directory,'dashboard.json'),restored);
  assert.equal(createStore(restored,f.options).getTimer(week).active.id,f.store.getTimer(week).active.id);
  const bad=JSON.parse(bytes); bad.timer.activeId='missing'; writeFileSync(f.file,JSON.stringify(bad)); const raw=readFileSync(f.file,'utf8');
  assert.throws(()=>createStore(f.file,f.options),/активный/); assert.equal(readFileSync(f.file,'utf8'),raw);
  assert.throws(()=>timerState({...bad.timer,revision:-1}),/хранилище/);
});
