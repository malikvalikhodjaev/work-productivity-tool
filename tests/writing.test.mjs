import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {IDBFactory} from 'fake-indexeddb';
import {replaceFile} from '../lib/atomic-file.mjs';
import {createWritingStore,writingDocument} from '../lib/writing.mjs';
import {createWritingDraftStore} from '../public/writing-drafts.js';
const document={ops:[{insert:'中文 · идея',attributes:{bold:true}},{insert:'\n',attributes:{header:1}},{insert:'Объяснение новичку\n'},{insert:'Почему это работает?\n',attributes:{header:4}}]};
function fixture(){const file=join(fs.mkdtempSync(join(tmpdir(),'iw-writing-')),'writing.json');let clock=Date.parse('2026-10-13T10:00:00+05:00');const options={now:()=>++clock,getToday:()=> '2026-10-13'};let store=createWritingStore(file,options);const packet=(changes={})=>({id:randomUUID(),requestId:randomUUID(),expectedRevision:0,instanceId:store.context().instanceId,action:'save',title:'Эссе',date:'2026-10-13',status:'draft',document,...changes});return {file,options,get store(){return store;},packet,reopen:()=>{store=createWritingStore(file,options);}};}
test('Архив по месяцам считает только публикации; дата, правки, корзина и восстановление не удваивают пост',()=>{
  const f=fixture(),draft=f.store.save(f.packet()).entry;
  assert.deepEqual(f.store.view().months,[]);assert.equal(f.store.view().counts.drafts,1);
  let post=f.store.save(f.packet({id:draft.id,expectedRevision:1,status:'published'})).entry;
  f.store.save(f.packet({date:'2026-09-30',status:'published'}));assert.deepEqual(f.store.view().months,[{month:'2026-10',count:1},{month:'2026-09',count:1}]);
  post=f.store.save(f.packet({id:post.id,expectedRevision:post.revision,status:'published',title:'Уточнённая тема'})).entry;
  assert.equal(f.store.view().counts.published,2);assert.equal(post.revisions.length,2);
  post=f.store.save(f.packet({id:post.id,expectedRevision:post.revision,action:'trash'})).entry;assert.equal(f.store.view().counts.published,1);assert.equal(f.store.view().counts.trash,1);
  post=f.store.save(f.packet({id:post.id,expectedRevision:post.revision,action:'restore'})).entry;assert.equal(f.store.view().counts.published,2);assert.equal(post.date,'2026-10-13');
  post=f.store.save(f.packet({id:post.id,expectedRevision:post.revision,status:'draft'})).entry;assert.equal(f.store.view().counts.published,1);f.reopen();assert.equal(f.store.get(post.id).status,'draft');
});
test('H1–H4, форматирование и Unicode сохраняются точно; прежний текст есть в истории и выгрузке',()=>{
  const f=fixture(),first=f.store.save(f.packet({status:'published'})).entry;const old=fs.readFileSync(f.file,'utf8');assert.deepEqual(f.store.get(first.id).document,document);assert.equal(fs.readFileSync(f.file,'utf8'),old);
  const changed={ops:[{insert:'Новый текст\n',attributes:{italic:true}}]};const next=f.store.save(f.packet({id:first.id,expectedRevision:1,status:'published',document:changed})).entry;
  assert.deepEqual(next.revisions[0].document,document);f.reopen();assert.deepEqual(f.store.get(first.id).document,changed);assert.equal(f.store.exportData().entries[0].revisions[0].document.ops[0].insert,'中文 · идея');
});
test('Повтор после потери ответа возвращает запись; устаревшая вкладка не переписывает новую версию',()=>{
  const f=fixture(),p=f.packet({status:'published'}),first=f.store.save(p).entry;f.reopen();assert.equal(f.store.save(p).duplicate,true);assert.equal(f.store.view().counts.published,1);
  f.store.save(f.packet({id:first.id,expectedRevision:1,title:'Новое'}));const raw=fs.readFileSync(f.file,'utf8');
  assert.throws(()=>f.store.save(f.packet({id:first.id,expectedRevision:1,title:'Устарело'})),e=>e.status===409);assert.throws(()=>f.store.save({...p,title:'Подмена'}),e=>e.status===409);assert.equal(fs.readFileSync(f.file,'utf8'),raw);
});
test('Некорректный формат, пустая публикация, будущая дата и другой архив не изменяют источник',()=>{
  const f=fixture(),raw=fs.readFileSync(f.file,'utf8');
  for(const doc of [{ops:[{insert:{image:'https://example.com/img'}}]},{ops:[{insert:'x\n',attributes:{header:5}}]},{ops:[{insert:'x',attributes:{link:'javascript:alert(1)'}}]}]) assert.throws(()=>f.store.save(f.packet({document:doc})));
  assert.throws(()=>f.store.save(f.packet({status:'published',title:''})),/тема и текст/);assert.throws(()=>f.store.save(f.packet({date:'2026-10-14'})),/Дата записи/);assert.throws(()=>f.store.save(f.packet({instanceId:randomUUID()})),e=>e.status===409);assert.equal(fs.readFileSync(f.file,'utf8'),raw);
  assert.deepEqual(writingDocument({ops:[{insert:'<script>alert(1)</script>\n'}]}).ops[0].insert,'<script>alert(1)</script>\n');
});
test('Сбой атомарной замены файла сохраняет прежний текст и память; испорченный источник не заменяется',()=>{
  const f=fixture(),first=f.store.save(f.packet()).entry,raw=fs.readFileSync(f.file,'utf8');
  const broken=createWritingStore(f.file,{...f.options,storage:{...fs,replaceFile:()=>{throw new Error('Disk failed');}}});assert.throws(()=>broken.save(f.packet({id:first.id,expectedRevision:1,title:'Не сохранено'})),/Disk failed/);assert.equal(broken.get(first.id).title,'Эссе');assert.equal(fs.readFileSync(f.file,'utf8'),raw);
  const bad=JSON.parse(raw);bad.entries[0].document={ops:[{insert:{image:'bad'}}]};fs.writeFileSync(f.file,JSON.stringify(bad));const bytes=fs.readFileSync(f.file);assert.throws(()=>createWritingStore(f.file,f.options),/текст/);assert.deepEqual(fs.readFileSync(f.file),bytes);
});
test('Поиск находит мысль внутри текста; сводка не выдаёт весь документ и не меняет общие месячные счётчики',()=>{
  const f=fixture();f.store.save(f.packet({status:'published',document:{ops:[{insert:'A'.repeat(400)+'\nНеизвестное место\n'}]}}));f.store.save(f.packet({title:'Другое',status:'published',date:'2026-09-12'}));
  const result=f.store.view('неизвестное');assert.equal(result.entries.length,1);assert.equal(result.entries[0].document,undefined);assert.equal(result.months.length,2);
});
test('Черновики разных вкладок сохраняются независимо; подтверждение старой версии не удаляет новые правки',async()=>{
  const factory=new IDBFactory(),a=createWritingDraftStore(factory),b=createWritingDraftStore(factory),record={key:'tab-a:post',token:'1:1',savedAt:'2026-10-13T10:00:00Z',content:{document}};
  await a.put(record);await b.put({...record,key:'tab-b:post'});await a.put({...record,token:'1:2'});await b.removeIf(record.key,'1:1');assert.equal((await a.list()).length,2);
  await a.close();const reopened=createWritingDraftStore(factory);assert.equal((await reopened.list()).find(r=>r.key===record.key).token,'1:2');assert.deepEqual((await reopened.list())[0].content.document,document);await reopened.removeIf(record.key,'1:2');assert.equal((await b.list()).length,1);await b.close();await reopened.close();
});
