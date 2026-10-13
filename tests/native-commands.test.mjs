import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { randomUUID } from 'node:crypto';
import { createStore, today } from '../lib/store.mjs';
import { createWorkspaceStore } from '../lib/workspace.mjs';
import { createDailyProblemStore } from '../lib/daily-problems.mjs';
import { replaceFile } from '../lib/atomic-file.mjs';

function fixture(){const root=fs.mkdtempSync(path.join(tmpdir(),'iw-native-'));let store;let workspace=createWorkspaceStore(path.join(root,'workspace.json'),()=>store.getPortfolio());store=createStore(path.join(root,'dashboard.json'),{validateWorkRef:workspace.validateRef,getEntities:workspace.entities});return {root,store,get workspace(){return workspace;},reopen(){workspace=createWorkspaceStore(path.join(root,'workspace.json'),()=>store.getPortfolio());}};}
const command=(module,action,input,extra={})=>({module,action,input,requestId:randomUUID(),expectedUpdatedAt:null,...extra});
test('Native case creation is durable and retry after a later edit cannot overwrite that edit',()=>{
  const f=fixture(),id=randomUUID();const create=command('workspace','saveCase',{clientId:id,title:'问题 · кейс',status:'active',context:'Исходник\n  строка',nextStep:'',resolution:''});
  f.workspace.nativeMutate(create);const first=f.workspace.view().cases[0];assert.equal(first.id,id);
  f.workspace.nativeMutate(command('workspace','saveCase',{id,title:'Уточнённый кейс',status:'watching',context:'Размышления',nextStep:'Проверить',resolution:''},{expectedUpdatedAt:first.updatedAt}));
  f.reopen();const repeated=f.workspace.nativeMutate(create);assert.equal(repeated.duplicate,true);assert.equal(repeated.workspace.cases.length,1);assert.equal(repeated.workspace.cases[0].title,'Уточнённый кейс');
  assert.throws(()=>f.workspace.nativeMutate({...create,input:{...create.input,title:'Подмена'}}),/UUID/);
  assert.throws(()=>f.workspace.nativeMutate(command('workspace','saveCase',{id,title:'Старая форма',status:'active',context:'',resolution:''},{expectedUpdatedAt:first.updatedAt})),/другом устройстве/);
});
test('Native receipt is not committed if atomic replacement fails',()=>{
  const root=fs.mkdtempSync(path.join(tmpdir(),'iw-native-fail-')),file=path.join(root,'workspace.json');let reject=false;
  const storage={...fs,replaceFile:(a,b)=>{if(reject)throw Error('disk unavailable');replaceFile(a,b);}};
  const store=createWorkspaceStore(file,()=>({projects:[],alphas:[],tasks:[]}),{storage});const input=command('workspace','saveCase',{clientId:randomUUID(),title:'Новый',status:'active'});reject=true;
  assert.throws(()=>store.nativeMutate(input),/disk/);assert.equal(store.view().cases.length,0);reject=false;assert.equal(store.nativeMutate(input).duplicate,false);assert.equal(store.view().cases.length,1);
});
test('Daily norm, hourly schedule and manual confirmation persist without fabricating time',()=>{
  const f=fixture(),id=randomUUID();f.workspace.nativeMutate(command('workspace','saveCase',{clientId:id,title:'Ежедневный кейс',status:'active'}));const ref='case:'+id;
  const norm=command('dailyNorm','save',{workRef:ref,minutes:60,time:'09:00',days:[1,2,3,4,5,6,7],enabled:true});f.store.nativeMutate(norm);f.store.nativeMutate(norm);
  const view=f.store.getDailyNorms();assert.equal(view.norms.length,1);assert.equal(view.repeatMinutes,60);assert.equal(view.norms[0].actualMinutes,null);
  f.store.nativeMutate(command('dailyCheck','save',{workRef:ref,date:today(),confirmed:true}));assert.equal(f.store.getStoredEntries().entries.length,0);assert.equal(f.store.getDailyNorms().checks[0].source,'manual_confirmation');
  const restored=createStore(path.join(f.root,'dashboard.json'),{validateWorkRef:f.workspace.validateRef,getEntities:f.workspace.entities});assert.equal(restored.getDailyNorms().norms[0].minutes,60);assert.equal(restored.getDailyNorms().checks[0].confirmed,true);
});
test('Invalid target for a future week commits neither defaults nor command receipt',()=>{
  const f=fixture();const file=path.join(f.root,'dashboard.json'),before=fs.readFileSync(file,'utf8');const week='2027-02-01';const metric=f.store.getWeek().metrics[0];
  const input=command('target','save',{week,metricId:metric.id,target:-4},{expectedTarget:metric.target});assert.throws(()=>f.store.nativeMutate(input),/Норматив/);assert.equal(fs.readFileSync(file,'utf8'),before);
  const fixed={...input,input:{...input.input,target:12}};assert.equal(f.store.nativeMutate(fixed).duplicate,false);assert.equal(f.store.getWeek(week).metrics[0].target,12);
});
test('Device identity is pinned to the server installation',()=>{
  const f=fixture(),deviceId=randomUUID(),context=f.store.offlineContext(deviceId);f.store.validateNativeDevice({deviceId,serverId:context.serverId});assert.throws(()=>f.store.validateNativeDevice({deviceId,serverId:randomUUID()}),/другой/);assert.throws(()=>f.store.validateNativeDevice({deviceId:randomUUID(),serverId:context.serverId}),/другой/);
});
test('Removed daily norm keeps its version so it can be restored after restart',()=>{
  const f=fixture(),id=randomUUID();f.workspace.nativeMutate(command('workspace','saveCase',{clientId:id,title:'Регулярный кейс',status:'active'}));const workRef='case:'+id;
  const save=(minutes,expectedUpdatedAt)=>f.store.nativeMutate(command('dailyNorm','save',{workRef,minutes,time:'09:30',days:[1,2,3,4,5,6,7],enabled:true},{expectedUpdatedAt}));
  save(60,null);save(null,f.store.getDailyNorms().norms[0].updatedAt);f.reopen();const removed=f.store.getDailyNorms().norms[0];assert.equal(removed.minutes,null);save(90,removed.updatedAt);assert.equal(f.store.getDailyNorms().norms[0].minutes,90);
});
test('Native day problem keeps a deterministic case link through response loss and restart',()=>{
  const f=fixture(),file=path.join(f.root,'daily-problems.json');let problems=createDailyProblemStore(file);const id=randomUUID(),input=command('problem','save',{date:today(),text:'  问题 · важный разрыв\nИсходник  ',expectedUpdatedAt:null});
  const problem=problems.nativeSave(input);const linked=f.workspace.ensureProblemCase(problem,id);assert.equal(linked.case.id,id);assert.equal(linked.case.context,input.input.text);
  problems=createDailyProblemStore(file);f.reopen();const repeated=problems.nativeSave(input);assert.equal(f.workspace.ensureProblemCase(repeated,id).created,false);assert.equal(f.workspace.view().cases.length,1);
});
