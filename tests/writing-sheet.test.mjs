import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {writingSheetUrl,writingHandoffPost} from '../public/writing-sheet.js';

test('The sheet and return routes contain identifiers, without the note text',()=>{
  const id=randomUUID(),handoff=randomUUID();
  assert.equal(writingSheetUrl({id,handoff}),`/write?handoff=${handoff}#writing/${id}`);
  assert.equal(writingSheetUrl({id,handoff,clean:false}),`/?handoff=${handoff}#writing/${id}`);
  assert.throws(()=>writingSheetUrl({id:'https://example.org',handoff}),/запись/);
});
test('A handoff keeps the same note identity, revision, formatting and raw paragraphs',()=>{
  const id=randomUUID(),instanceId=randomUUID(),document={ops:[{insert:'  Моя мысль · 思考\n\n',attributes:{bold:true}},{insert:'Ещё строка  \n'}]},
    record={content:{id,instanceId,expectedRevision:7,title:'  Тема  ',date:'2026-10-19',status:'draft',favorite:true,document}};
  const result=writingHandoffPost(record,{instanceId,id});
  assert.equal(result.id,id);assert.equal(result.revision,7);assert.equal(result.title,'  Тема  ');assert.equal(result.favorite,true);assert.deepEqual(result.document,document);
  result.document.ops[0].insert='Другая запись';assert.notEqual(record.content.document.ops[0].insert,'Другая запись');
  assert.throws(()=>writingHandoffPost(record,{instanceId:randomUUID(),id}),/другой записи или архиву/);
  assert.throws(()=>writingHandoffPost(record,{instanceId,id:randomUUID()}),/другой записи или архиву/);
});
