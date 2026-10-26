import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {createWorkspaceStore} from '../lib/workspace.mjs';

function fixture(t) {
  const dir=mkdtempSync(path.join(tmpdir(),'iw-goal-grid-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));
  const file=path.join(dir,'workspace.json'),portfolio=()=>({projects:[],tasks:[],alphas:[]});
  const store=createWorkspaceStore(file,portfolio);
  const goal=store.mutate('saveGoal',{title:'Домашнее хозяйство',unit:'ч',direction:'down',status:'active',physicalSystem:'  Моё домашнее\nхозяйство  '}).goals[0];
  return {file,store,goal,portfolio};
}
test('physical system and renamed built-in columns preserve raw text, IDs and measurement meaning',t=>{
  const {file,store,goal}=fixture(t);
  assert.equal(goal.physicalSystem,'  Моё домашнее\nхозяйство  ');
  assert.equal(store.view().goalTableHistory[0].value,goal.physicalSystem);
  store.mutate('measure',{kind:'goal',targetId:goal.id,date:'2026-10-26',value:0,evidence:'Исходное'});
  const before=structuredClone(store.view().measurements);
  store.mutate('updateGoalColumn',{id:'title',title:'  Моя характеристика  ',expectedRevision:0});
  const column=store.view().goalColumnDefinitions.find(c=>c.id==='title');
  assert.equal(column.title,'  Моя характеристика  ');assert.equal(column.revision,1);
  assert.equal(store.view().goals[0].title,goal.title);assert.deepEqual(store.view().measurements,before);
  const raw=readFileSync(file,'utf8');
  assert.throws(()=>store.mutate('updateGoalColumn',{id:'title',title:'Другая подпись',expectedRevision:0}),/изменилось/);
  assert.throws(()=>store.mutate('updateGoalColumn',{id:'unit',title:'  МОЯ ХАРАКТЕРИСТИКА ',expectedRevision:0}),/уже есть/);
  assert.equal(readFileSync(file,'utf8'),raw);
});
test('typed custom cells merge independently, reject stale before, and survive repeat and restart',t=>{
  const {file,store,goal,portfolio}=fixture(t),text=randomUUID(),number=randomUUID();
  for(const [id,type,title] of [[text,'text','Контекст'],[number,'number','Объём']])store.mutate('createGoalColumn',{id,type,title});
  const command={requestId:randomUUID(),action:'editGoalCell',input:{id:goal.id,columnId:text,before:null,value:'  исходный\nтекст  '}};
  store.nativeMutate(command);store.mutate('editGoalCell',{id:goal.id,columnId:number,before:null,value:0});
  const raw=readFileSync(file,'utf8');store.nativeMutate(command);assert.equal(readFileSync(file,'utf8'),raw);
  assert.equal(store.view().goals[0].updatedAt,goal.updatedAt);
  assert.throws(()=>store.mutate('editGoalCell',{id:goal.id,columnId:text,before:null,value:'Заменить'}),/изменилась/);
  assert.throws(()=>store.mutate('editGoalCell',{id:goal.id,columnId:number,before:0,value:'12'}),/число/);
  assert.throws(()=>store.mutate('editGoalCell',{id:goal.id,columnId:'current',before:null,value:12}),/недоступны/);
  assert.equal(readFileSync(file,'utf8'),raw);
  const reopened=createWorkspaceStore(file,portfolio).view();
  assert.equal(reopened.goalGridVersion,1);assert.equal(reopened.goals[0].customValues[text],'  исходный\nтекст  ');assert.equal(reopened.goals[0].customValues[number],0);
  assert.equal(reopened.goalTableHistory.filter(h=>h.rowId===goal.id&&[text,number].includes(h.columnId)).length,2);
});
test('select, date, checkbox and archived column validation never rewrites old values',t=>{
  const {store,goal}=fixture(t);
  for(const [type,value,bad] of [['select','Один','Три'],['date','2026-10-27','2026-02-30'],['checkbox',false,'false']]){
    const id=randomUUID();store.mutate('createGoalColumn',{id,title:type,type,...(type==='select'?{options:{'Один':'Один','Два':'Два'}}:{})});
    store.mutate('editGoalCell',{id:goal.id,columnId:id,before:null,value});
    assert.throws(()=>store.mutate('editGoalCell',{id:goal.id,columnId:id,before:value,value:bad}));
    store.mutate('updateGoalColumn',{id,title:type,expectedRevision:1,archived:true});
    assert.equal(store.view().goals[0].customValues[id],value);
    assert.equal(store.view().goalColumnDefinitions.some(c=>c.id===id),false);
  }
});
