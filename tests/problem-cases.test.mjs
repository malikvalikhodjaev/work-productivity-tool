import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {createWorkspaceStore} from '../lib/workspace.mjs';
import {createDailyProblemStore} from '../lib/daily-problems.mjs';
import {createStore,today} from '../lib/store.mjs';
import {replaceFile} from '../lib/atomic-file.mjs';

function fixture(){const root=fs.mkdtempSync(path.join(tmpdir(),'iw-problem-case-'));let clock=Date.now();let store;const file=path.join(root,'workspace.json');let workspace=createWorkspaceStore(file,()=>store.getPortfolio());store=createStore(path.join(root,'dashboard.json'),{now:()=>clock,validateWorkRef:ref=>workspace.validateRef(ref),getEntities:()=>workspace.entities()});const problems=createDailyProblemStore(path.join(root,'daily-problems.json'));return {root,file,problems,get workspace(){return workspace;},store,advance:seconds=>{clock+=seconds*1000;},reopen:()=>{workspace=createWorkspaceStore(file,()=>store.getPortfolio());}};}

test('Проблема сохраняет исходный текст, один кейс и устойчивую связь таймера после перезапуска',()=>{
  const f=fixture(),problem=f.problems.save({date:today(),text:'  模型 · важный разрыв\nПроверить первый результат  ',expectedUpdatedAt:null});
  const first=f.workspace.ensureProblemCase(problem),ref='case:'+first.case.id;assert.equal(first.created,true);assert.equal(first.case.context,problem.text);assert.equal(first.case.dailyProblem.original.text,problem.text);
  const raw=fs.readFileSync(f.file,'utf8');assert.equal(f.workspace.ensureProblemCase(problem).created,false);assert.equal(fs.readFileSync(f.file,'utf8'),raw);
  const start=f.store.mutateTimer('start',{title:problem.text.trim(),workRef:ref,mode:'pomodoro',metricId:null,allocation:'unclassified',workType:'Диагностика',expectedRevision:0,requestId:randomUUID()}).active;
  f.advance(60);f.store.mutateTimer('finish',{sessionId:start.id,observation:'Выяснил причину',expectedRevision:1,requestId:randomUUID()});f.reopen();
  assert.equal(f.workspace.problemCase(today()).id,first.case.id);assert.equal(f.workspace.view().cases.length,1);assert.equal(f.store.getStoredEntries().entries[0].workRef,ref);assert.equal(f.store.getTimer().byWork[0].seconds,60);
});

test('Правка проблемы добавляет формулировку и сохраняет ручной контекст, состояние, заметки и предыдущий исходник',()=>{
  const f=fixture(),problem=f.problems.save({date:today(),text:'Недостаточно данных о результате',expectedUpdatedAt:null});const original=f.workspace.ensureProblemCase(problem).case;
  f.workspace.mutate('saveCase',{...original,title:'Мой кейс',context:'Мои размышления',nextStep:'Проверить с пользователем',status:'watching'});
  f.workspace.mutate('saveWorkNote',{workRef:'case:'+original.id,text:'  Свободная заметка  ',expectedRevision:0,requestId:randomUUID()});
  const next=f.problems.save({date:today(),text:'Не проверено принятие результата пользователем',expectedUpdatedAt:problem.updatedAt});const linked=f.workspace.ensureProblemCase(next).case;
  assert.equal(linked.id,original.id);assert.equal(linked.title,'Мой кейс');assert.equal(linked.context,'Мои размышления');assert.equal(linked.status,'watching');assert.equal(linked.dailyProblem.original.text,problem.text);assert.equal(linked.dailyProblem.versions.length,2);assert.equal(linked.dailyProblem.versions[1].text,next.text);assert.equal(f.workspace.view().workNotes[0].text,'  Свободная заметка  ');
  assert.throws(()=>f.problems.save({date:today(),text:'Устаревший ввод',expectedUpdatedAt:problem.updatedAt}),/уже изменена/);assert.equal(f.workspace.view().cases.length,1);
});

test('Точная повторная проблема в другой день и ранее созданный кейс используются без дубля',()=>{
  const f=fixture();const existing=f.workspace.mutate('saveCase',{title:'Нет проверки',context:'Нет проверки',status:'active'}).cases[0];
  const first=f.problems.save({date:'2020-01-01',text:'Нет проверки',expectedUpdatedAt:null});assert.equal(f.workspace.ensureProblemCase(first).case.id,existing.id);
  const next=f.problems.save({date:today(),text:'Нет проверки',expectedUpdatedAt:null});assert.equal(f.workspace.ensureProblemCase(next).case.id,existing.id);f.reopen();
  assert.equal(f.workspace.problemCase('2020-01-01').id,existing.id);assert.equal(f.workspace.problemCase(today()).id,existing.id);assert.equal(f.workspace.view().cases.length,1);
  const other=f.problems.save({date:'2020-01-02',text:'Другая проблема',expectedUpdatedAt:null});assert.notEqual(f.workspace.ensureProblemCase(other).case.id,existing.id);assert.equal(f.workspace.view().cases.length,2);
});

test('Сбой записи кейса сохраняет проблему и исходное хранилище; повтор после восстановления создаёт один кейс',()=>{
  const f=fixture();f.workspace.mutate('saveCase',{title:'Прежний кейс',context:'Исходник',status:'new'});const raw=fs.readFileSync(f.file,'utf8');const problem=f.problems.save({date:today(),text:'Длинный разрыв '.repeat(30),expectedUpdatedAt:null});
  const broken=createWorkspaceStore(f.file,()=>f.store.getPortfolio(),{storage:{...fs,replaceFile:()=>{throw new Error('Disk failed');}}});assert.throws(()=>broken.ensureProblemCase(problem),/Disk failed/);assert.equal(fs.readFileSync(f.file,'utf8'),raw);assert.equal(broken.view().cases.length,1);assert.equal(f.problems.view().entries[0].text,problem.text);
  f.reopen();const saved=f.workspace.ensureProblemCase(problem).case;assert.ok(saved.title.length<=200);assert.equal(saved.context,problem.text);assert.equal(f.workspace.ensureProblemCase(problem).created,false);assert.equal(f.workspace.view().cases.length,2);
});
