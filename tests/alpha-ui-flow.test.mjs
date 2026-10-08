import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createStore } from '../lib/store.mjs';
import { writeLegacyAlphaFixture } from './alpha-fixture.mjs';

// A small DOM contract harness exercises the actual page script and store together.
// This checks event flows; it is not a browser rendering or visual-layout test.
test('Скрипт страницы загружает старый объект, сохраняет заметку, создаёт именованный объект и восстанавливает черновик', async () => {
  const html=readFileSync(new URL('../public/alphas.html',import.meta.url),'utf8');
  const elements=new Map(); const drafts=new Map();
  for (const match of html.matchAll(/<(\w+)\b[^>]*\bid="([^"]+)"[^>]*>/g)) {
    const [,tag,id]=match; let markup=''; let currentValue='';
    elements.set(id, {
      id,tagName:tag.toUpperCase(),hidden:match[0].includes('hidden'),disabled:match[0].includes('disabled'),checked:false,options:[],handlers:new Map(),textContent:'',
      classList:{toggle(){}},focus(){},closest(){return {childNodes:[{textContent:id}]}},reportValidity(){return Boolean(elements.get('uniqueName').value)},
      add(option){this.options.push(option)},addEventListener(event,handler){this.handlers.set(event,handler)},
      get value(){return currentValue},set value(value){currentValue=String(value)},
      get innerHTML(){return markup},set innerHTML(value){markup=value; if(this.tagName==='SELECT')this.options=[...value.matchAll(/<option value="([^"]*)">([^<]*)<\/option>/g)].map(item=>({value:item[1],text:item[2]}));},
      showModal(){this.open=true},close(){this.open=false}
    });
  }
  const file=path.join(mkdtempSync(path.join(tmpdir(),'alpha-ui-')),'dashboard.json'); writeLegacyAlphaFixture(file); const store=createStore(file);
  const document={getElementById(id){assert.ok(elements.has(id),`Missing HTML control: ${id}`);return elements.get(id)}};
  const fetch=async (url,options)=>{
    let payload; let ok=true;
    try {
      if(url==='/api/portfolio') payload=options?.method==='POST'?store.updatePortfolio(...((body)=>[body.action,body.input])(JSON.parse(options.body))):store.getPortfolio();
      else if(url==='/api/imported-data') payload={reference:{rows:[{alpha:'Клиентура',state:'Пользовательское состояние'}]}};
      else if(url==='/api/daily-results') payload={today:'2026-10-09',entries:[]};
      else if(url.startsWith('/api/alphas/history')) payload={entries:store.alphaHistory(new URL(url,'http://localhost').searchParams.get('id'))};
      else throw new Error(`Unexpected route: ${url}`);
    }catch(error){ok=false;payload={error:error.message}}
    return {ok,json:async()=>structuredClone(payload)};
  };
  const context=vm.createContext({document,fetch,Intl,Date,JSON,Map,Set,Option:function(text,value){return {text,value}},URL,URLSearchParams,location:{search:'',origin:'http://localhost'},Blob,setTimeout,window:{confirm:()=>true,addEventListener(){}},localStorage:{getItem:key=>drafts.get(key)??null,setItem:(key,value)=>drafts.set(key,value),removeItem:key=>drafts.delete(key)}});
  vm.runInContext(readFileSync(new URL('../public/alphas.js',import.meta.url),'utf8'),context);
  await new Promise(resolve=>setTimeout(resolve,10));
  assert.equal(elements.get('editor-form').hidden,false,elements.get('notice').textContent);
  assert.equal(elements.get('uniqueName').value,'Клиентура тестового проекта');
  elements.get('description').value='Запись со страницы';
  elements.get('editor-form').handlers.get('input')();
  await elements.get('editor-form').handlers.get('submit')({preventDefault(){}});
  assert.equal(store.getPortfolio().alphas[0].description,'Запись со страницы');
  assert.equal(elements.get('save-state').textContent,'Без изменений');
  assert.equal(drafts.size,0);
  elements.get('new').handlers.get('click')();
  elements.get('uniqueName').value='Конкретный новый объект';elements.get('description').value='Можно без имени альфы';
  elements.get('editor-form').handlers.get('input')();
  await elements.get('editor-form').handlers.get('submit')({preventDefault(){}});
  assert.equal(store.getPortfolio().alphas.length,4); assert.equal(store.getPortfolio().alphas.at(-1).typeName,'');
  assert.equal(elements.get('editor-title').textContent,'Конкретный новый объект');
  assert.equal(elements.get('projectId').disabled,true);
  elements.get('description').value='Ещё не сохранённый черновик';elements.get('editor-form').handlers.get('input')();
  assert.equal(drafts.size,1);
  vm.runInContext('openEditor(selectedId, false)',context);
  assert.equal(elements.get('draft-banner').hidden,false);
  elements.get('restore-draft').handlers.get('click')();
  assert.equal(elements.get('description').value,'Ещё не сохранённый черновик');
  assert.equal(store.getPortfolio().alphas.at(-1).description,'Можно без имени альфы');
  await elements.get('editor-form').handlers.get('submit')({preventDefault(){}});
  assert.equal(createStore(file).getPortfolio().alphas.at(-1).description,'Ещё не сохранённый черновик');
});
