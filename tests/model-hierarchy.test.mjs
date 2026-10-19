import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdtempSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {hierarchyRows,hierarchySignature,relocateAlpha} from '../public/model-hierarchy.js';
import {createStore} from '../lib/store.mjs';
import {compileReferenceTemplate} from '../lib/project-templates.mjs';

const source={capturedAt:'2026-10-19',sources:{catalog:'https://example.org/catalog'},rows:[
  {sourceId:'area',level:'Уровень 1 — область интересов',area:'Целевая система',parentId:null},
  {sourceId:'system',level:'Уровень 2 — альфа',area:'Целевая система',alpha:'Система',parentId:'area'},
  {sourceId:'state',level:'Уровень 3 — состояние альфы',area:'Целевая система',alpha:'Система',state:'Описана',parentId:'system'},
  {sourceId:'question',level:'Уровень 4 — контрольный вопрос',area:'Целевая система',alpha:'Система',question:'Какие границы системы?',parentId:'state'},
  {sourceId:'part',level:'Уровень 3 — подальфа',area:'Целевая система',alpha:'Часть системы',parentId:'system'},
]};
const fixture=()=>{const file=path.join(mkdtempSync(path.join(tmpdir(),'iw-tree-')),'dashboard.json'),definition=compileReferenceTemplate(source);return {file,definition,store:createStore(file,{getProjectTemplates:()=>[definition]})};};
const instantiate=(store,def,name='Проект')=>{
  const clientId=randomUUID(),input={templateId:def.id,expectedVersion:def.version,clientId,name,alphaIds:Object.fromEntries(def.alphas.map(a=>[a.sourceId,randomUUID()]))},requestId=randomUUID();
  return {input,requestId,result:store.mutatePortfolioGrid('copyProject',input,requestId)};
};
test('WBS numbers remain stable when collapsed; moving carries descendants and protects raw text',()=>{
  const rows=[{id:'a',projectId:'p',zoneId:'z',parentId:null,description:'  Моя запись\nПродолжение  '},{id:'b',projectId:'p',zoneId:'z',parentId:null},{id:'c',projectId:'p',zoneId:'z',parentId:'a'},{id:'d',projectId:'p',zoneId:'z',parentId:'c'}];
  assert.deepEqual(hierarchyRows(rows).map(x=>[x.row.id,x.wbs]),[['a','1'],['c','1.1'],['d','1.1.1'],['b','2']]);
  assert.deepEqual(hierarchyRows(rows,new Set(['a'])).map(x=>x.wbs),['1','2']);
  const moved=relocateAlpha(rows,{id:'c',parentId:'b'});
  assert.deepEqual(hierarchyRows(moved).map(x=>x.wbs),['1','2','2.1','2.1.1']);
  assert.equal(moved[0].description,rows[0].description);assert.equal(rows[2].parentId,'a');
  assert.throws(()=>relocateAlpha(rows,{id:'a',parentId:'d'}),/потомка/);
  assert.throws(()=>relocateAlpha([...rows,{id:'x',projectId:'other',zoneId:'x'}],{id:'a',parentId:'x'}),/том же проекте/);
});
test('Template copy creates fresh empty instances with a frozen source and state/question hints; UUID retry is atomic',()=>{
  const {file,store,definition}=fixture(),created=instantiate(store,definition);
  const project=created.result.projects[0],nodes=created.result.alphas;
  assert.equal(nodes.length,2);assert.equal(nodes[1].parentId,nodes[0].id);assert.equal(project.summary.filled,0);
  assert.equal(nodes[0].templateStates[0].questions[0].text,'Какие границы системы?');
  assert.equal(nodes[0].uniqueName,'');assert.equal(nodes[0].state,'empty');assert.equal(nodes[0].filledDate,null);
  const saved=readFileSync(file,'utf8');
  assert.equal(store.mutatePortfolioGrid('copyProject',created.input,created.requestId).duplicate,true);
  assert.equal(readFileSync(file,'utf8'),saved);
  const exported=store.alphaBackup(),destination=fixture();destination.store.importAlphas(exported,true);
  assert.equal(destination.store.getPortfolio().alphas[0].templateStates[0].title,'Описана');
  assert.equal(destination.store.alphaBackup().templateVersions[definition.version].sourceRows.length,5);
  assert.equal(store.getWeek('2026-10-19').entries.length,0);
});
test('Hierarchy has optimistic concurrency and a permanent receipt; moving is included in alpha history and export',()=>{
  const {file,store,definition}=fixture(),created=instantiate(store,definition),nodes=created.result.alphas;
  const input={id:nodes[1].id,parentId:null,expectedHierarchy:hierarchySignature(nodes)},id=randomUUID();
  store.mutatePortfolioGrid('moveAlpha',input,id);const saved=readFileSync(file,'utf8');
  assert.throws(()=>store.mutatePortfolioGrid('moveAlpha',{...input,parentId:nodes[0].id},randomUUID()),e=>e.status===409);
  assert.equal(readFileSync(file,'utf8'),saved);
  assert.equal(store.mutatePortfolioGrid('moveAlpha',input,id).duplicate,true);
  assert.equal(store.getPortfolio().alphas[1].parentId,null);
  assert.ok(store.alphaHistory(nodes[1].id).some(h=>h.action==='edit'&&h.snapshot.parentId===null));
  assert.equal(store.alphaBackup().alphas[1].sortOrder,1);
});
test('Copying an existing project preserves only structure and rejects a changed source; an empty project can be copied',()=>{
  const {store,definition}=fixture();const created=instantiate(store,definition);const node=created.result.alphas[0];
  store.mutatePortfolioGrid('editCells',{table:'alphas',id:node.id,changes:[
    {columnId:'description',before:'',value:'  Мои факты\nВторая строка  '},{columnId:'uniqueName',before:'',value:'Мой объект'},
    {columnId:'state',before:'empty',value:'verified'},{columnId:'criteria',before:'',value:'Критерий'},{columnId:'evidence',before:'',value:'Свидетельство'},
    {columnId:'filledDate',before:null,value:'2026-10-19'},
  ]},randomUUID());
  const project=store.getPortfolio().projects[0],copyInput={sourceProjectId:project.id,expectedVersion:project.copyVersion,clientId:randomUUID(),name:'Копия',alphaIds:Object.fromEntries(store.getPortfolio().alphas.map(a=>[a.id,randomUUID()]))};
  store.mutatePortfolioGrid('copyProject',copyInput,randomUUID());
  const copied=store.getPortfolio().alphas.filter(a=>a.projectId===copyInput.clientId);
  assert.equal(copied[0].description,'');assert.equal(copied[0].filledDate,null);assert.equal(copied[0].uniqueName,'');assert.equal(copied[0].templateStates.length,1);assert.equal(copied[0].state,'empty');assert.equal(copied[0].evidence,'');
  assert.equal(store.getPortfolio().alphas.find(a=>a.id===node.id).description,'  Мои факты\nВторая строка  ');
  store.updatePortfolio('updateAlpha',{...store.getPortfolio().alphas[0],nextStep:'Уточнить'});
  assert.throws(()=>store.mutatePortfolioGrid('copyProject',{...copyInput,clientId:randomUUID()},randomUUID()),e=>e.status===409);
  store.updatePortfolio('createProject',{name:'Пустой',status:'active',phase:'pre_operation',zoneIds:['customers']});
  const empty=store.getPortfolio().projects.at(-1),id=randomUUID();store.mutatePortfolioGrid('copyProject',{sourceProjectId:empty.id,expectedVersion:empty.copyVersion,clientId:id,name:'Пустая копия',alphaIds:{}},randomUUID());
  assert.ok(store.getPortfolio().projects.some(p=>p.id===id));
});
test('Pending native copy can be edited using counters before server timestamps are known; stale counters still reject changes',()=>{
  const {store,definition}=fixture(),created=instantiate(store,definition),project=created.result.projects[0],node=created.result.alphas[0];
  const alphaCommand={requestId:randomUUID(),module:'portfolio',action:'updateAlpha',expectedUpdatedAt:null,input:{...node,uniqueName:'Своё имя',description:'Моя запись',expectedRevision:1}};
  store.nativeMutate(alphaCommand);
  assert.equal(store.getPortfolio().alphas[0].revision,2);
  assert.throws(()=>store.nativeMutate({...alphaCommand,requestId:randomUUID()}),/уже изменена/);
  const projectCommand={requestId:randomUUID(),module:'portfolio',action:'updateProject',expectedUpdatedAt:null,input:{...project,name:'Свой проект',zoneIds:project.zones.map(z=>z.id),expectedRevision:1}};
  store.nativeMutate(projectCommand);
  assert.equal(store.getPortfolio().projects[0].revision,2);
  store.mutatePortfolioGrid('editCells',{table:'projects',id:project.id,changes:[{columnId:'status',before:'active',value:'paused'}]},randomUUID());
  assert.equal(store.getPortfolio().projects[0].revision,3);
  assert.throws(()=>store.nativeMutate({...projectCommand,requestId:randomUUID(),input:{...projectCommand.input,expectedRevision:2}}),/уже изменена/);
});
