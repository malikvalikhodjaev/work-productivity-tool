import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { createStore } from '../lib/store.mjs';
import { pomodoroFacts, pomodoroPlanView } from '../lib/pomodoro-plans.mjs';

const date = '2026-10-15', ref = 'task:reading';
function fixture() {
  const file = path.join(mkdtempSync(path.join(tmpdir(), 'iw-pom-plan-')), 'dashboard.json');
  let clock = Date.parse(`${date}T10:00:00+05:00`);
  const options = { now: () => clock, validateWorkRef: r => { if (r == null) return null; if (![ref,'task:guides'].includes(r)) throw Error('Unknown work'); return r; }, getEntities: () => [{ref, title:'Другое имя работы'},{ref:'task:guides',title:'Руководства'}] };
  let store = createStore(file, options);
  return { file, get store() { return store; }, advance(s) { clock += s * 1000; }, reopen() { store = createStore(file, options); },
    command(target, expectedUpdatedAt = null, extra = {}) { return { module:'pomodoroTarget', action:'save', requestId:randomUUID(), expectedUpdatedAt, input:{workRef:ref, date, title:'  Чтение · 我的规范  ', target, repeat:'once', ...extra} }; },
    timer(action, input = {}) { return store.mutateTimer(action, { ...input, week:date, requestId:randomUUID(), expectedRevision:store.getTimer(date).revision }); } };
}

test('Explicit add never replaces a current or inherited norm; editing remains available', () => {
  const f=fixture();
  f.store.nativeMutate(f.command(10,null,{repeat:'daily',create:true}));
  const before=readFileSync(f.file,'utf8');
  assert.throws(()=>f.store.nativeMutate(f.command(2,null,{create:true,title:'Вторая норма'})),/уже есть норматив/);
  assert.throws(()=>f.store.nativeMutate(f.command(2,null,{create:true,date:'2026-10-16'})),/уже есть норматив/);
  assert.equal(readFileSync(f.file,'utf8'),before);
  const old=f.store.getDailyNorms(date).pomodoroTargets[0];
  f.store.nativeMutate(f.command(2,old.updatedAt,{title:'Редактируемая норма'}));
  assert.equal(f.store.getDailyNorms(date).pomodoroPlan.targets[0].title,'Редактируемая норма');
});

test('Two different works keep independent daily norms and timer counts after restart', () => {
  const f=fixture();
  f.store.nativeMutate(f.command(10,null,{repeat:'daily',create:true}));
  const second=f.command(2,null,{workRef:'task:guides',title:'Руководства',repeat:'daily',create:true});
  f.store.nativeMutate(second);f.store.nativeMutate(second);
  const s=f.timer('start',{title:'Чтение',mode:'pomodoro',metricId:'reading',allocation:'assigned',workRef:ref}).active;
  f.advance(1500);f.timer('finish',{sessionId:s.id});f.reopen();
  const view=f.store.getDailyNorms(date),first=view.pomodoroPlan.targets.find(t=>t.workRef===ref),other=view.pomodoroPlan.targets.find(t=>t.workRef==='task:guides');
  assert.equal(view.pomodoroPlan.targets.length,2);assert.equal(first.target,10);assert.equal(first.actualPomodoros,1);assert.equal(other.target,2);assert.equal(other.actualPomodoros,0);
  assert.equal(view.pomodoroWeek.rows.length,2);
});

test('Daily counts are backed by complete work sessions, deduplicated and assigned to Tashkent completion day', () => {
  const s = {id:'same',workRef:ref,status:'finished',phase:'work',mode:'pomodoro',completedPomodoros:1,finishedAt:'2026-10-14T19:01:00Z'};
  assert.deepEqual(pomodoroFacts([s,s,{...s,id:'break',phase:'short_break'},{...s,id:'partial',completedPomodoros:0},{...s,id:'cancel',status:'cancelled'},{...s,id:'stopwatch',mode:'stopwatch'},{...s,id:'excluded',syncResolution:'excluded'}]), [{sessionId:'same',workRef:ref,date,count:1}]);
});

test('Free completed pomodoros count once globally without fulfilling an unrelated norm',()=>{
 const f=fixture();f.store.nativeMutate(f.command(2));
 const session=f.timer('start',{title:'Активность без норматива',mode:'pomodoro',metricId:null,allocation:'outside',workRef:null}).active;
 f.advance(1500);f.timer('finish',{sessionId:session.id});f.reopen();
 const data=f.store.getDailyNorms(date);
 assert.deepEqual(data.pomodoroFacts,[{sessionId:session.id,workRef:null,date,count:1}]);
 assert.equal(data.pomodoroPlan.targets[0].actualPomodoros,0);
 const original=f.store.getTimer(date).sessions.find(s=>s.id===session.id);
 assert.equal(pomodoroFacts([original,original]).length,1);
 assert.equal(f.store.getStoredEntries().entries.length,1);
});

test('Exact names, daily reset, removal/restoration and safe retries survive restart', () => {
  const f=fixture(), command=f.command(10);
  f.store.nativeMutate(command); f.reopen(); f.store.nativeMutate(command);
  let view=f.store.getDailyNorms(date); assert.equal(view.pomodoroPlan.hasPlan,true); assert.equal(view.pomodoroPlan.targets[0].title,command.input.title); assert.equal(view.pomodoroPlan.targets[0].actualPomodoros,0);
  assert.equal(f.store.getDailyNorms('2026-10-16').pomodoroPlan.hasPlan,false);
  const row=view.pomodoroTargets[0]; f.store.nativeMutate(f.command(null,row.updatedAt)); f.reopen();
  view=f.store.getDailyNorms(date); assert.equal(view.pomodoroPlan.hasPlan,false); assert.equal(view.pomodoroTargets[0].target,null);
  assert.throws(()=>f.store.nativeMutate(f.command(1,row.updatedAt)),/другом устройстве/);
  f.store.nativeMutate(f.command(1,view.pomodoroTargets[0].updatedAt)); assert.equal(f.store.getDailyNorms(date).pomodoroPlan.targets[0].target,1);
});

test('A complete real timer advances the norm exactly once; hours/manual confirmations do not fabricate pomodoros', () => {
  const f=fixture(); f.store.nativeMutate(f.command(1));
  const s=f.timer('start',{title:'Чтение',mode:'pomodoro',metricId:'reading',allocation:'assigned',workRef:ref}).active;
  f.advance(600); f.timer('pause',{sessionId:s.id}); f.advance(600); f.timer('resume',{sessionId:s.id}); f.advance(900);
  const finish={week:date,requestId:randomUUID(),expectedRevision:f.store.getTimer(date).revision,sessionId:s.id};
  f.store.mutateTimer('finish',finish); f.store.mutateTimer('finish',finish); f.reopen();
  assert.equal(f.store.getDailyNorms(date).pomodoroPlan.targets[0].actualPomodoros,1);
  assert.equal(f.store.getDailyNorms(date).pomodoroWeek.rows[0].actualPomodoros,1);
  assert.equal(f.store.getStoredEntries().entries.length,1);
});

test('Week totals use the plans actually set for each date and never infer a plan for missing dates', () => {
  const targets=[{workRef:ref,date:'2026-10-14',title:'Название',target:1},{workRef:ref,date,title:'Название',target:10}];
  const view=pomodoroPlanView({pomodoroTargets:targets},date);
  assert.equal(view.pomodoroWeek.week,'2026-10-12'); assert.equal(view.pomodoroWeek.rows[0].target,11); assert.equal(view.pomodoroWeek.rows[0].days.length,2);
  assert.equal(view.pomodoroPlan.targets[0].target,10);
});

test('Invalid counts and dates leave the original file and receipts unchanged', () => {
  const f=fixture(), before=readFileSync(f.file,'utf8');
  for (const target of [0,-1,1.5,1441,'10']) assert.throws(()=>f.store.nativeMutate(f.command(target)),/Норма/);
  const missing=f.command(1); delete missing.input.target; assert.throws(()=>f.store.nativeMutate(missing),/Норма/);
  assert.throws(()=>f.store.nativeMutate(f.command(1,null,{date:'2026-02-30'})),/дату/);
  assert.equal(readFileSync(f.file,'utf8'),before);
});

test('Recurring daily targets survive midnight and restart indefinitely without copying yesterday facts', () => {
  const f=fixture(), command=f.command(10,null,{repeat:'daily'});
  f.store.nativeMutate(command);f.store.nativeMutate(command);f.reopen();
  for(const day of ['2026-10-16','2026-11-15','2036-10-15']){
    const view=f.store.getDailyNorms(day).pomodoroPlan;
    assert.equal(view.hasPlan,true);assert.equal(view.targets[0].title,command.input.title);
    assert.equal(view.targets[0].target,10);assert.equal(view.targets[0].actualPomodoros,0);
  }
  assert.equal(f.store.getDailyNorms('2026-10-14').pomodoroPlan.hasPlan,false);
  assert.equal(JSON.parse(readFileSync(f.file,'utf8')).pomodoroTargets.length,1);
});

test('Editing and removing recurring plans changes future days while preserving past plans and facts', () => {
  const f=fixture();f.store.nativeMutate(f.command(10,null,{repeat:'daily'}));
  f.store.nativeMutate(f.command(2,null,{date:'2026-10-17',repeat:'daily'}));
  f.store.nativeMutate(f.command(null,null,{date:'2026-10-19',repeat:'daily'}));f.reopen();
  assert.equal(f.store.getDailyNorms('2026-10-16').pomodoroPlan.targets[0].target,10);
  assert.equal(f.store.getDailyNorms('2026-10-18').pomodoroPlan.targets[0].target,2);
  assert.equal(f.store.getDailyNorms('2036-10-15').pomodoroPlan.hasPlan,false);
  assert.equal(f.store.getDailyNorms('2026-10-18').pomodoroWeek.rows[0].target,24);
});

test('Legacy dated plans remain dated and a recurring replacement does not rewrite their original records', () => {
  const legacy={workRef:ref,date:'2026-10-14',title:'  Мой норматив  ',target:10};
  const recurring={...legacy,date:'2026-10-16',repeat:'daily'};
  const original=structuredClone(legacy), data={pomodoroTargets:[legacy,recurring]};
  assert.equal(pomodoroPlanView(data,'2026-10-15').pomodoroPlan.hasPlan,false);
  assert.equal(pomodoroPlanView(data,'2026-10-17').pomodoroPlan.targets[0].target,10);
  assert.deepEqual(legacy,original);
});

test('New commands default to daily and invalid repeat values preserve the source', () => {
  const f=fixture(), c=f.command(1);delete c.input.repeat;
  f.store.nativeMutate(c);assert.equal(f.store.getDailyNorms('2036-10-15').pomodoroPlan.hasPlan,true);
  const before=readFileSync(f.file,'utf8');
  assert.throws(()=>f.store.nativeMutate(f.command(1,null,{repeat:'sometimes',date:'2026-10-16'})),/Повтор/);
  assert.equal(readFileSync(f.file,'utf8'),before);
});


test('Norm time type survives restart, legacy edits and validation without rewriting completed sessions', () => {
  const f=fixture();
  f.store.nativeMutate(f.command(3,null,{workType:'investment'}));
  const session=f.timer('start',{title:'Чтение',mode:'pomodoro',metricId:null,allocation:'outside',workRef:ref,workType:'productive'}).active;
  f.advance(1500);f.timer('finish',{sessionId:session.id});
  const original=f.store.getTimer(date).sessions.find(s=>s.id===session.id);
  let row=f.store.getDailyNorms(date).pomodoroTargets[0];
  f.store.nativeMutate(f.command(4,row.updatedAt));f.reopen();
  row=f.store.getDailyNorms(date).pomodoroTargets[0];
  assert.equal(row.workType,'investment');
  assert.equal(row.revisions[0].workType,'investment');
  assert.deepEqual(f.store.getTimer(date).sessions.find(s=>s.id===session.id),original);
  const before=readFileSync(f.file,'utf8');
  assert.throws(()=>f.store.nativeMutate(f.command(4,row.updatedAt,{workType:'guessed-waste'})),/типы? времени/);
  assert.equal(readFileSync(f.file,'utf8'),before);
  f.store.nativeMutate(f.command(4,row.updatedAt,{workType:''}));
  assert.equal(f.store.getDailyNorms(date).pomodoroTargets[0].workType,'');
});


test('Legacy client changing a future daily norm keeps its inherited time type',()=>{
  const f=fixture();f.store.nativeMutate(f.command(3,null,{repeat:'daily',workType:'investment'}));
  f.store.nativeMutate(f.command(4,null,{repeat:'daily',date:'2026-10-16'}));
  assert.equal(f.store.getDailyNorms('2026-10-16').pomodoroPlan.targets[0].workType,'investment');
  assert.equal(f.store.getDailyNorms(date).pomodoroPlan.targets[0].workType,'investment');
});

test('Combined norm types roundtrip without rewriting facts; invalid combinations leave data and receipts intact',()=>{
  const f=fixture();
  const command=f.command(3,null,{repeat:'daily',workType:'investment+productive'});
  f.store.nativeMutate(command);f.store.nativeMutate(command);f.reopen();
  let row=f.store.getDailyNorms(date).pomodoroTargets[0];
  assert.equal(row.workType,'investment+productive');
  const session=f.timer('start',{title:'Работа',mode:'pomodoro',metricId:null,allocation:'outside',workRef:ref,workType:row.workType}).active;
  assert.equal(session.workType,'investment+productive');
  f.advance(1500);f.timer('finish',{sessionId:session.id});
  const original=f.store.getTimer(date).sessions;
  const before=readFileSync(f.file,'utf8');
  for(const workType of ['investment+investment','investment+unknown','investment+','unclassified',null,42,[]]){
    assert.throws(()=>f.store.nativeMutate(f.command(3,row.updatedAt,{workType})),/типы времени/);
    assert.equal(readFileSync(f.file,'utf8'),before);
  }
  f.store.nativeMutate(f.command(4,null,{date:'2026-10-16',repeat:'daily'}));f.reopen();
  assert.equal(f.store.getDailyNorms('2026-10-16').pomodoroPlan.targets[0].workType,'investment+productive');
  assert.deepEqual(f.store.getTimer(date).sessions,original);
  assert.equal(f.store.getDailyNorms(date).pomodoroPlan.targets[0].actualPomodoros,1);
});
