import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {goalHierarchySignature,goalSiblings,relocateGoal} from '../lib/goal-hierarchy.mjs';
import {createWorkspaceStore} from '../lib/workspace.mjs';

const sample=()=>[
  {id:'a',title:'  Исходный\nтекст  ',sortOrder:0,status:'active',physicalSystem:'  Дом  ',customValues:{note:'\nraw '},updatedAt:'old'},
  {id:'b',parentId:'a',sortOrder:0,title:'Дочерняя',status:'active'},
  {id:'c',parentId:'b',sortOrder:0,title:'Глубже',status:'active'},
  {id:'d',sortOrder:1,title:'Другая',status:'active'},
  {id:'e',sortOrder:2,title:'Архив',status:'archived'},
];
test('branch order, nesting, root promotion and canonical signature preserve UUIDs and raw values',()=>{
  const source=sample(),raw=JSON.stringify(source);
  assert.equal(goalHierarchySignature(source),'[["a",null,0,false,null],["b","a",0,false,null],["c","b",0,false,null],["d",null,1,false,null],["e",null,2,true,null]]');
  let moved=relocateGoal(source,{id:'d',parentId:null,beforeId:'a'});
  assert.deepEqual(goalSiblings(moved).map(r=>r.id),['d','a','e']);
  moved=relocateGoal(moved,{id:'a',parentId:'d'});
  assert.equal(moved.find(r=>r.id==='a').parentId,'d');
  assert.equal(moved.find(r=>r.id==='c').parentId,'b');
  moved=relocateGoal(moved,{id:'b',parentId:null,beforeId:'d'});
  assert.deepEqual(goalSiblings(moved).map(r=>r.id),['b','d','e']);
  assert.deepEqual(moved.find(r=>r.id==='a').customValues,source[0].customValues);
  assert.equal(moved.find(r=>r.id==='a').title,source[0].title);
  assert.equal(moved.find(r=>r.id==='a').updatedAt,'old');
  assert.equal(JSON.stringify(source),raw);
});
test('cycles, absent targets and archived or deleted ancestry never mutate the source',()=>{
  const source=sample(),raw=JSON.stringify(source);
  for(const input of [{id:'a',parentId:'c'},{id:'a',parentId:'a'},{id:'a',parentId:'missing'},
    {id:'a',beforeId:'missing'},{id:'a',parentId:'e'},{id:'e',parentId:null},{id:'a',beforeId:'b'}]) {
    assert.throws(()=>relocateGoal(source,input));assert.equal(JSON.stringify(source),raw);
  }
  const trash=source.map(r=>r.id==='a'?{...r,trashedAt:'2026-10-27T00:00:00Z'}:r);
  assert.throws(()=>relocateGoal(trash,{id:'b',parentId:null}),/восстанови/);
});
test('native move is atomic, guarded, idempotent, survives restart and stale full-row drafts cannot undo it',t=>{
  const dir=mkdtempSync(path.join(tmpdir(),'iw-goal-move-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));
  const file=path.join(dir,'workspace.json'),portfolio=()=>({projects:[],tasks:[],alphas:[]});
  const store=createWorkspaceStore(file,portfolio),save=(title,parentId=null)=>store.mutate('saveGoal',{title,parentId,unit:'ч',direction:'up',status:'active'}).goals.at(-1);
  const a=save('Система'),b=save('Подцель',a.id),c=save('Другая система');
  store.mutate('measure',{kind:'goal',targetId:b.id,date:'2026-10-26',value:0,evidence:'  raw\nfact  '});
  const facts=structuredClone(store.view().measurements),signature=goalHierarchySignature(store.view().goals);
  const command={requestId:randomUUID(),action:'moveGoal',input:{id:b.id,parentId:c.id,beforeId:null,expectedHierarchy:signature}};
  store.nativeMutate(command);const raw=readFileSync(file,'utf8');store.nativeMutate(command);
  assert.equal(readFileSync(file,'utf8'),raw);assert.equal(store.view().goals.find(g=>g.id===b.id).parentId,c.id);
  assert.deepEqual(store.view().measurements,facts);
  assert.throws(()=>store.nativeMutate({...command,requestId:randomUUID()}),e=>e.status===409);
  assert.throws(()=>store.nativeMutate({requestId:randomUUID(),action:'saveGoal',expectedUpdatedAt:b.updatedAt,input:{...b,title:'New'}}),e=>e.status===409);
  assert.equal(readFileSync(file,'utf8'),raw);
  const reopened=createWorkspaceStore(file,portfolio);
  assert.equal(reopened.view().goalHierarchyVersion,1);
  assert.equal(reopened.view().goals.find(g=>g.id===b.id).parentId,c.id);
  assert.equal(reopened.view().goalTableHistory.filter(h=>h.action==='moveGoal').length,1);
  reopened.nativeMutate({requestId:randomUUID(),action:'saveGoal',expectedUpdatedAt:b.updatedAt,input:{...b,parentId:c.id,expectedParentId:c.id,title:'Новое имя'}});
  assert.equal(reopened.view().goals.find(g=>g.id===b.id).title,'Новое имя');
  assert.deepEqual(reopened.view().measurements,facts);
});
