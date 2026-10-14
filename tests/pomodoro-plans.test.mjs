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
  const options = { now: () => clock, validateWorkRef: r => { if (r !== ref) throw Error('Unknown work'); return r; }, getEntities: () => [{ref, title:'Другое имя работы'}] };
  let store = createStore(file, options);
  return { file, get store() { return store; }, advance(s) { clock += s * 1000; }, reopen() { store = createStore(file, options); },
    command(target, expectedUpdatedAt = null, extra = {}) { return { module:'pomodoroTarget', action:'save', requestId:randomUUID(), expectedUpdatedAt, input:{workRef:ref, date, title:'  Чтение · 我的规范  ', target, ...extra} }; },
    timer(action, input = {}) { return store.mutateTimer(action, { ...input, week:date, requestId:randomUUID(), expectedRevision:store.getTimer(date).revision }); } };
}

test('Daily counts are backed by complete work sessions, deduplicated and assigned to Tashkent completion day', () => {
  const s = {id:'same',workRef:ref,status:'finished',phase:'work',mode:'pomodoro',completedPomodoros:1,finishedAt:'2026-10-14T19:01:00Z'};
  assert.deepEqual(pomodoroFacts([s,s,{...s,id:'break',phase:'short_break'},{...s,id:'partial',completedPomodoros:0},{...s,id:'cancel',status:'cancelled'},{...s,id:'stopwatch',mode:'stopwatch'},{...s,id:'excluded',syncResolution:'excluded'}]), [{sessionId:'same',workRef:ref,date,count:1}]);
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
