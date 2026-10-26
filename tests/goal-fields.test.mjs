import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {createWorkspaceStore} from '../lib/workspace.mjs';
import {goalHierarchySignature} from '../lib/goal-hierarchy.mjs';
const fixture=t=>{
 const dir=mkdtempSync(path.join(tmpdir(),'iw-goal-fields-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));
 const file=path.join(dir,'workspace.json'),portfolio=()=>({projects:[],tasks:[],alphas:[]});
 const store=createWorkspaceStore(file,portfolio);
 const goal=store.mutate('saveGoal',{title:'Мастерство',unit:'ч',direction:'up',status:'active'}).goals[0];
 const command=(field,before,value)=>({requestId:randomUUID(),action:'editGoalFields',input:{id:goal.id,changes:[{field,before,value}]}});
 return {store,goal,file,portfolio,command};
};
test('independent fields save without waiting for the same row, preserve raw text and replay exactly once',t=>{
 const {store,goal,file,portfolio,command}=fixture(t);
 const title=command('title',goal.title,'  Прорывы от руководств, мастерство  '),unit=command('unit',goal.unit,'кол-во времени вложенного в работу в неделю');
 store.nativeMutate(unit);store.nativeMutate(title);
 const raw=readFileSync(file,'utf8');store.nativeMutate(unit);store.nativeMutate(title);assert.equal(readFileSync(file,'utf8'),raw);
 const row=store.view().goals[0];assert.equal(row.title,title.input.changes[0].value);assert.equal(row.unit,unit.input.changes[0].value);
 assert.throws(()=>store.nativeMutate(command('title',goal.title,'Старая версия')),e=>e.status===409);
 assert.equal(readFileSync(file,'utf8'),raw);
 const reopened=createWorkspaceStore(file,portfolio).view();assert.equal(reopened.goalFieldEditingVersion,1);assert.equal(reopened.goalTextLimits.unit,200);
 assert.equal(reopened.goals[0].unit,row.unit);assert.equal(reopened.goalTableHistory.filter(h=>h.action==='editGoalFields').length,2);
});
test('types are explicit, survive old clients, and reject unknown choices atomically',t=>{
 const {store,goal,file,command}=fixture(t);
 assert.equal(store.view().goals[0].characteristicType,undefined);
  assert.equal(store.view().goalColumnDefinitions.some(c=>c.id==='characteristicType'),false);
  assert.equal(store.view().characteristicColumnDefinitions[0].id,'characteristicType');
 for(const type of ['indicator','monitoring','guardrail',null]) {
  const before=store.view().goals[0].characteristicType??null;
  store.nativeMutate(command('characteristicType',before,type));
  assert.equal(store.view().goals[0].characteristicType,type);
 }
 store.nativeMutate(command('characteristicType',null,'guardrail'));
 const row=store.view().goals[0];const {characteristicType,...legacy}=row;
 store.nativeMutate({requestId:randomUUID(),action:'saveGoal',expectedUpdatedAt:row.updatedAt,input:{...legacy,title:'Другое имя'}});
 assert.equal(store.view().goals[0].characteristicType,'guardrail');
  store.mutate('updateGoalColumn',{id:'characteristicType',title:'Мой тип характеристики',expectedRevision:0});
  assert.equal(store.view().goalColumns.some(c=>c.id==='characteristicType'),false);
  assert.equal(store.view().characteristicColumnDefinitions[0].title,'Мой тип характеристики');
 const raw=readFileSync(file,'utf8');assert.throws(()=>store.nativeMutate(command('characteristicType','guardrail','mystery')));
 assert.equal(readFileSync(file,'utf8'),raw);
});
test('long units are validated before a transaction and measured units retain their meaning',t=>{
 const {store,goal,file,command}=fixture(t),raw=readFileSync(file,'utf8');
 assert.throws(()=>store.nativeMutate(command('unit','ч','я'.repeat(201))),/200/);
 assert.throws(()=>store.nativeMutate({requestId:randomUUID(),action:'editGoalFields',input:{id:goal.id,changes:[{field:'title',before:goal.title,value:'Не записать'},{field:'current',before:null,value:3}]}}));
 assert.equal(readFileSync(file,'utf8'),raw);
 store.mutate('measure',{kind:'goal',targetId:goal.id,date:'2026-10-26',value:0,evidence:'Нулевой замер'});
 const facts=structuredClone(store.view().measurements);
 assert.throws(()=>store.nativeMutate(command('unit','ч','дни')),/Не меняй источник или единицу/);
 store.nativeMutate(command('characteristicType',null,'monitoring'));assert.deepEqual(store.view().measurements,facts);
});
test('field patches retain a moved parent and an unchanged legacy command may retry after the old unit limit',t=>{
 const {store,goal,command}=fixture(t);
 const legacy={requestId:randomUUID(),action:'saveGoal',expectedUpdatedAt:goal.updatedAt,input:{...goal,unit:'кол-во времени вложенного в работу'}};
 store.nativeMutate(legacy);
 const parent=store.mutate('saveGoal',{title:'Система',unit:'шт',direction:'up',status:'active'}).goals.at(-1);
 store.nativeMutate({requestId:randomUUID(),action:'moveGoal',input:{id:goal.id,parentId:parent.id,expectedHierarchy:goalHierarchySignature(store.view().goals)}});
 store.nativeMutate(command('title',goal.title,'  Другое имя  '));
 assert.equal(store.view().goals[0].parentId,parent.id);assert.equal(store.view().goals[0].title,'  Другое имя  ');
});
