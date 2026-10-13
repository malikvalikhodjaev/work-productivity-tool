import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createWorkspaceStore} from '../lib/workspace.mjs';
import {createStore,monday,today} from '../lib/store.mjs';

function fixture(){
  const dir=mkdtempSync(join(tmpdir(),'iw-work-items-'));let store,now=Date.parse(today()+'T10:00:00+05:00');
  const workspace=createWorkspaceStore(join(dir,'workspace.json'),()=>store.getPortfolio());
  const options={validateWorkRef:workspace.validateRef,getEntities:workspace.entities,now:()=>now};
  store=createStore(join(dir,'dashboard.json'),options);
  const input=(extra={})=>({title:'Проверить первую версию',kind:'work',stage:'planned',description:'\n  Свободная мысль\n',nextStep:'Проверить результат',metricId:'guides',allocation:'assigned',workType:'Создание',expectedRevision:0,requestId:randomUUID(),...extra});
  return {dir,workspace,input,get store(){return store;},advance:seconds=>now+=seconds*1000,reopen:()=>store=createStore(join(dir,'dashboard.json'),options)};
}

test('Старое хранилище кейсов открывается без перезаписи исходника и получает пустую доску',()=>{
  const f=fixture();f.workspace.mutate('saveCase',{title:'Старый кейс',status:'active',context:'Мой контекст'});
  const file=join(f.dir,'workspace.json'),raw=readFileSync(file,'utf8');
  const reopened=createWorkspaceStore(file,()=>f.store.getPortfolio());
  assert.equal(readFileSync(file,'utf8'),raw);assert.deepEqual(reopened.view().workItems,[]);assert.equal(reopened.view().cases[0].context,'Мой контекст');
});
test('Карточка хранит свободный текст, версии и повтор запроса; конфликт не затирает работу',()=>{
  const f=fixture(),input=f.input();const first=f.workspace.mutate('saveWorkItem',input).workItems[0];
  assert.equal(first.description,input.description);assert.equal(first.originalDescription,input.description);
  const file=join(f.dir,'workspace.json'),raw=readFileSync(file,'utf8');f.workspace.mutate('saveWorkItem',input);assert.equal(readFileSync(file,'utf8'),raw);
  f.workspace.mutate('saveWorkItem',f.input({id:first.id,expectedRevision:1,description:'Новая мысль',stage:'active'}));
  const current=f.workspace.view().workItems[0];assert.equal(current.revision,2);assert.equal(current.revisions[0].description,input.description);
  assert.throws(()=>f.workspace.mutate('saveWorkItem',f.input({id:first.id,expectedRevision:1,description:'Устаревшая мысль'})),/другой вкладке/);
  assert.equal(f.workspace.view().workItems[0].description,'Новая мысль');
  assert.throws(()=>f.workspace.mutate('saveWorkItem',f.input({id:first.id,expectedRevision:2,stage:'operation',result:''})),/результат/);
});
test('Повторное взятие строки Coda не создаёт дубль; исходник переживает правки',()=>{
  const f=fixture(),origin={type:'coda',table:'issues',sourceId:'row-test',snapshot:{title:'Источник',note:'  Исходные данные\n',status:'Неясно'}};
  const item=f.workspace.mutate('saveWorkItem',f.input({kind:'issue',origin})).workItems[0];
  assert.throws(()=>f.workspace.mutate('saveWorkItem',f.input({kind:'issue',origin})),/уже взята/);
  f.workspace.mutate('saveWorkItem',f.input({id:item.id,expectedRevision:1,title:'Уточнённая ситуация',origin:{...origin,snapshot:{note:'Другой'}}}));
  assert.deepEqual(f.workspace.view().workItems[0].origin.snapshot,origin.snapshot);
});
test('Запуск из карточки, пауза и продолжение сохраняют события, исключают паузу и учитывают время один раз',()=>{
  const f=fixture(),item=f.workspace.mutate('saveWorkItem',f.input()).workItems[0],ref='work:'+item.id,week=monday(today());
  const act=(action,input={})=>f.store.mutateTimer(action,{...input,week,expectedRevision:f.store.getTimer(week).revision,requestId:randomUUID()});
  const session=act('start',{title:item.title,workRef:ref,metricId:'guides',allocation:'assigned',workType:'Создание',mode:'stopwatch'}).active;
  f.advance(20);act('pause',{sessionId:session.id});f.advance(50);f.reopen();act('resume',{sessionId:session.id});f.advance(30);
  const finish={sessionId:session.id,week,expectedRevision:f.store.getTimer(week).revision,requestId:randomUUID()};f.store.mutateTimer('finish',finish);f.store.mutateTimer('finish',finish);
  const history=f.store.getTimerHistory(ref);assert.equal(history.sessions.length,1);assert.deepEqual(history.sessions[0].events.map(e=>e.action),['start','pause','resume','finish']);
  assert.deepEqual(history.sessions[0].events.map(e=>e.elapsedSeconds),[0,20,20,50]);assert.equal(history.sessions[0].elapsedMs,50000);
  const records=f.store.getStoredEntries().entries;assert.equal(records.length,1);assert.equal(records[0].workRef,ref);assert.equal(records[0].durationSeconds,50);
  assert.equal(f.store.getTimer(week).events.length,4);
});
test('Заметки существующей задачи имеют версии и сохраняют карточку проекта',()=>{
  const f=fixture();f.store.updatePortfolio('createProject',{name:'Проект',status:'active',phase:'pre_operation',zoneIds:['customers']});const project=f.store.getPortfolio().projects[0];
  f.store.updatePortfolio('createTask',{projectId:project.id,title:'Задача',beforeOperation:true});const task=f.store.getPortfolio().tasks[0],ref='task:'+task.id;
  f.workspace.mutate('saveWorkNote',{workRef:ref,text:'\nРазмышление\n',expectedRevision:0,requestId:randomUUID()});
  f.workspace.mutate('saveWorkNote',{workRef:ref,text:'Уточнение',expectedRevision:1,requestId:randomUUID()});
  const note=f.workspace.view().workNotes[0];assert.equal(note.revisions[0].text,'\nРазмышление\n');assert.deepEqual(f.store.getPortfolio().tasks[0],task);
});
