import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {createStore} from '../lib/store.mjs';
import {createWorkspaceStore} from '../lib/workspace.mjs';
import {writeLegacyAlphaFixture} from './alpha-fixture.mjs';
import {checkedModelUrl} from '../lib/model-url.mjs';

test('alpha model links survive cell edits, raw history, export and import',t=>{
  const dir=mkdtempSync(path.join(tmpdir(),'iw-model-link-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));
  const file=path.join(dir,'dashboard.json');writeLegacyAlphaFixture(file);const store=createStore(file);
  const alpha=store.getPortfolio().alphas[0],url='https://example.org/model?a=1#alpha';
  store.mutatePortfolioGrid('editCells',{table:'alphas',id:alpha.id,changes:[{columnId:'modelUrl',before:null,value:url}]},randomUUID());
  assert.equal(store.getPortfolio().alphas.find(a=>a.id===alpha.id).modelUrl,url);
  assert.equal(store.alphaHistory(alpha.id).at(-1).snapshot.modelUrl,url);
  const backup=store.alphaBackup();
  const destination=createStore(path.join(dir,'other.json'));
  destination.importAlphas(backup,true);
  assert.equal(destination.getPortfolio().alphas.find(a=>a.id===alpha.id).modelUrl,url);
  const before=readFileSync(file,'utf8');
  assert.throws(()=>store.mutatePortfolioGrid('editCells',{table:'alphas',id:alpha.id,changes:[{columnId:'modelUrl',before:url,value:'javascript:alert(1)'}]},randomUUID()),/HTTP/);
  assert.equal(readFileSync(file,'utf8'),before);
  assert.equal(checkedModelUrl('  https://example.org/#original  '),'  https://example.org/#original  ');
});
test('goal stages accept work-stage vocabulary and preserve legacy values without changing measurements',t=>{
  const dir=mkdtempSync(path.join(tmpdir(),'iw-goal-stage-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));
  const workspace=createWorkspaceStore(path.join(dir,'workspace.json'),()=>({projects:[],alphas:[],tasks:[]}));
  let goal=workspace.mutate('saveGoal',{title:'Проверить цель',unit:'шт',status:'active',direction:'up'}).goals[0];
  workspace.mutate('measure',{kind:'goal',targetId:goal.id,date:'2026-10-26',value:3,evidence:'  raw\n evidence  '});
  const measurements=structuredClone(workspace.view().measurements);
  for(const status of ['note','planned','active','commissioning','ready','operation','blocked','retired','paused','archived']){
    goal=workspace.mutate('saveGoal',{...goal,status}).goals[0];assert.equal(goal.status,status);
  }
  assert.deepEqual(workspace.view().measurements,measurements);
  assert.throws(()=>workspace.mutate('saveGoal',{...goal,status:'unknown'}));
});
