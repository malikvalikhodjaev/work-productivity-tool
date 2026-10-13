import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {createWritingStore,writingDocument} from '../lib/writing.mjs';
import {writingPlainText} from '../public/writing-editor.js';

test('Разделитель восстанавливается с форматированием, историей и выгрузкой, не создавая лишние слова',()=>{
  const file=join(mkdtempSync(join(tmpdir(),'iw-divider-')),'writing.json'),store=createWritingStore(file);const document={ops:[{insert:'Первое\n',attributes:{header:2}},{insert:{divider:true}},{insert:'Второе\n'}]};
  const first=store.save({action:'save',id:randomUUID(),requestId:randomUUID(),expectedRevision:0,instanceId:store.context().instanceId,title:'Разделы',date:store.context().today,status:'published',document}).entry;
  const reopened=createWritingStore(file);assert.deepEqual(reopened.get(first.id).document,document);assert.equal(reopened.view().entries[0].words,2);assert.equal(reopened.view().counts.published,1);assert.equal(reopened.view('Второе').entries.length,1);assert.ok(writingPlainText(document).includes('---'));assert.ok(!writingPlainText(document).includes('[object Object]'));
  reopened.save({action:'save',id:first.id,requestId:randomUUID(),expectedRevision:1,instanceId:reopened.context().instanceId,title:'Разделы',date:first.date,status:'published',document:{ops:[{insert:'Другая версия\n'}]}});assert.deepEqual(reopened.get(first.id).revisions[0].document,document);assert.equal(reopened.view().counts.published,1);assert.deepEqual(reopened.exportData().entries[0].revisions[0].document,document);
});

test('Неизвестные вставки, атрибуты линии и пустая публикация не меняют архив',()=>{
  const file=join(mkdtempSync(join(tmpdir(),'iw-divider-invalid-')),'writing.json'),store=createWritingStore(file),raw=readFileSync(file,'utf8');
  for(const insert of [{divider:false},{divider:'<script>'},{divider:true,html:'onclick'},{image:'x'}])assert.throws(()=>writingDocument({ops:[{insert},{insert:'\n'}]}));
  assert.throws(()=>writingDocument({ops:[{insert:{divider:true},attributes:{link:'https://example.com'}},{insert:'\n'}]}));assert.throws(()=>writingDocument({ops:[{insert:{divider:true}}]}),/переводом строки/);
  assert.throws(()=>store.save({action:'save',id:randomUUID(),requestId:randomUUID(),expectedRevision:0,instanceId:store.context().instanceId,title:'Только линия',date:store.context().today,status:'published',document:{ops:[{insert:{divider:true}},{insert:'\n'}]}}),/тема и текст/);assert.equal(readFileSync(file,'utf8'),raw);
});
