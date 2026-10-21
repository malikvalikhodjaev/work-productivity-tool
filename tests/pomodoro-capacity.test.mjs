import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createStore } from '../lib/store.mjs';
import { pomodoroPlanView } from '../lib/pomodoro-plans.mjs';
import { pomodoroCapacitySummary } from '../public/pomodoro-capacity.js';

const day='2026-10-21';
const targets=[{date:day,repeat:'daily',workRef:'task:a',title:'  A  ',target:10},
  {date:day,repeat:'daily',workRef:'task:b',title:'B',target:8}];
const rules=[{date:day,limit:15}];
test('sum of independent norms warns only above personal capacity; editing replaces one contribution',()=>{
  const summary=pomodoroCapacitySummary(targets,rules,day);
  assert.equal(summary.planned,18);assert.equal(summary.limit,15);assert.equal(summary.over,true);
  assert.match(summary.message,/18.*15/);
  assert.equal(pomodoroCapacitySummary(targets,rules,day,{workRef:'task:b',target:5}).over,false);
  assert.equal(pomodoroCapacitySummary(targets,rules,day,{workRef:'task:b',target:null}).planned,10);
  assert.equal(pomodoroCapacitySummary(targets,[],day).limit,null);
  assert.equal(pomodoroCapacitySummary(targets,[],day).over,false);
});
test('effective daily capacity preserves history, supports removal, and appears in week totals',()=>{
  const view=pomodoroPlanView({pomodoroTargets:targets,pomodoroCapacities:[...rules,{date:'2026-10-23',limit:30},{date:'2026-10-24',limit:null}]},day);
  assert.equal(view.pomodoroPlan.capacity.over,true);
  assert.deepEqual(view.pomodoroWeek.capacities.map(c=>[c.date,c.planned,c.limit,c.over]),[
    ['2026-10-19',0,null,false],['2026-10-20',0,null,false],['2026-10-21',18,15,true],
    ['2026-10-22',18,15,true],['2026-10-23',18,30,false],['2026-10-24',18,null,false],['2026-10-25',18,null,false],
  ]);
  assert.equal(view.pomodoroPlan.targets[0].title,'  A  ');
});
test('capacity survives restart and retry; stale or invalid edits leave files untouched; timers remain available',()=>{
  const file=path.join(mkdtempSync(path.join(tmpdir(),'iw-cap-')),'dashboard.json');
  const opts={now:()=>Date.parse(`${day}T10:00:00+05:00`)};
  let store=createStore(file,opts);
  const command=(limit,date=day,expectedUpdatedAt=null)=>({module:'pomodoroCapacity',action:'save',requestId:randomUUID(),expectedUpdatedAt,input:{date,limit}});
  const first=command(15);store.nativeMutate(first);store=createStore(file,opts);store.nativeMutate(first);
  const saved=store.getDailyNorms(day).pomodoroCapacities[0];
  assert.equal(store.getDailyNorms('2036-01-01').pomodoroPlan.capacity.limit,15);
  const before=readFileSync(file,'utf8');
  for(const limit of [0,-1,1.5,'15',1441])assert.throws(()=>store.nativeMutate(command(limit)),/лимит/);
  const missing=command(15);delete missing.input.limit;assert.throws(()=>store.nativeMutate(missing),/лимит/);
  assert.throws(()=>store.nativeMutate(command(30)),/другом устройстве/);
  assert.throws(()=>store.nativeMutate(command(30,'2026-02-30')),/дату/);
  assert.equal(readFileSync(file,'utf8'),before);
  store.nativeMutate(command(30,day,saved.updatedAt));
  const revised=store.getDailyNorms(day).pomodoroCapacities[0];
  assert.equal(revised.revisions[0].limit,15);
  assert.notEqual(revised.updatedAt,saved.updatedAt);
  store.nativeMutate(command(null,'2026-10-22'));
  assert.equal(store.getDailyNorms(day).pomodoroPlan.capacity.limit,30);
  assert.equal(store.getDailyNorms('2026-10-22').pomodoroPlan.capacity.limit,null);
  const started=store.mutateTimer('start',{title:'Work',mode:'pomodoro',metricId:'reading',allocation:'assigned',week:day,requestId:randomUUID(),expectedRevision:store.getTimer(day).revision});
  assert.equal(started.active.status,'running');
});
