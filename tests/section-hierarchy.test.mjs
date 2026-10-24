import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createWorkspaceStore} from '../lib/workspace.mjs';
import {createStore} from '../lib/store.mjs';
import {modelActivity} from '../lib/model-activity.mjs';

test('goal decomposition survives old-client edits; cycles and missing parents leave data intact',t=>{
  const dir=fs.mkdtempSync(path.join(tmpdir(),'iw-goal-tree-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  const file=path.join(dir,'workspace.json'),store=createWorkspaceStore(file,()=>({projects:[],tasks:[],alphas:[]}));
  const save=(title,extra={})=>store.mutate('saveGoal',{title,unit:'шт',baseline:0,target:10,direction:'up',...extra});
  const root=save('Корень').goals[0],child=save('Подцель',{parentId:root.id}).goals[1];
  save('Переименовал',{id:child.id});assert.equal(store.view().goals[1].parentId,root.id);
  const before=fs.readFileSync(file,'utf8');
  assert.throws(()=>save('Корень',{id:root.id,parentId:child.id}),/потомка/);
  assert.throws(()=>save('Подцель',{id:child.id,parentId:'missing'}),/не найден/);
  assert.equal(fs.readFileSync(file,'utf8'),before);
  assert.equal(createWorkspaceStore(file,()=>({projects:[],tasks:[],alphas:[]})).view().goals[1].parentId,root.id);
});
test('project hierarchy edits work in table cells and reject a cyclic move atomically',t=>{
  const dir=fs.mkdtempSync(path.join(tmpdir(),'iw-project-tree-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  const store=createStore(path.join(dir,'dashboard.json'));
  const create=(name,parentId=null)=>store.updatePortfolio('createProject',{name,parentId,status:'active',phase:'pre_operation',zoneIds:['customers']});
  const root=create('Корень').projects[0],child=create('Подпроект',root.id).projects[1];
  const parentColumn=store.getPortfolio().tableDefinitions.projects.find(c=>c.id==='parentId');
  assert.equal(parentColumn.options[root.id],'Корень');
  assert.throws(()=>store.updatePortfolio('editCells',{table:'projects',id:root.id,changes:[{columnId:'parentId',before:null,value:child.id}]}),/потомка/);
  assert.equal(store.getPortfolio().projects[0].parentId,null);
  store.updatePortfolio('editCells',{table:'projects',id:child.id,changes:[{columnId:'parentId',before:root.id,value:null}]});
  assert.equal(store.getPortfolio().projects[1].parentId,null);
});
test('model activity counts saved changes and new text, excluding imports and baseline',()=>{
  const snap={uniqueName:'',typeName:'Клиентура',description:'',criteria:'',evidence:'',nextStep:''};
  const edited={...snap,uniqueName:'Клиенты дома',description:'Одна\nДве строки'};
  const backup={projects:[{id:'p'}],alphas:[{id:'a',projectId:'p',...edited}],history:[
    {alphaId:'a',action:'baseline',at:'2026-10-19T00:00:00Z',snapshot:snap},
    {alphaId:'a',action:'edit',at:'2026-10-20T00:00:00Z',snapshot:edited},
    {alphaId:'b',action:'import',at:'2026-10-20T00:00:00Z',snapshot:edited},
  ]};
  const result=modelActivity(backup,'2026-10-19');
  assert.deepEqual(result.activity,{created:0,edits:1,renames:1,filled:1,addedLines:2});
  assert.equal(result.adapted,1);assert.equal(result.byProject[0].activity.renames,1);
  assert.equal(modelActivity(backup,'2026-10-26').activity.edits,0);
});
