import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, writeFileSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {readReflectionHints} from '../lib/reflection-hints.mjs';

test('подсказки читают только разрешённые адреса и не отдают исходные личные тексты', () => {
  const dir=mkdtempSync(join(tmpdir(),'reflection-')), file=join(dir,'reflection-hints.json');
  const raw=JSON.stringify({sources:{oz:{url:'https://example.com/oz'},lift:{url:'https://example.com/lift'},musk:{url:'javascript:alert(1)'},done:{url:'https://secret@example.com/post'},unknown:{url:'https://example.com/private'}},doneQuote:'What did you get done this week?',originalText:'личный полный текст'});
  writeFileSync(file,raw);
  assert.deepEqual(readReflectionHints(dir),{sources:{oz:{url:'https://example.com/oz'},lift:{url:'https://example.com/lift'}},doneQuote:'What did you get done this week?'});
  assert.equal(readFileSync(file,'utf8'),raw);
});

test('подсказки сохраняют связь с прежним шаблоном и работают без нового конфига', () => {
  const dir=mkdtempSync(join(tmpdir(),'reflection-'));
  writeFileSync(join(dir,'writing-hints.json'),JSON.stringify({url:'https://example.com/template#section'}));
  assert.deepEqual(readReflectionHints(dir),{sources:{feynman:{url:'https://example.com/template#section'}},doneQuote:null});
  writeFileSync(join(dir,'reflection-hints.json'),'{broken');
  assert.equal(readReflectionHints(dir).sources.feynman.url,'https://example.com/template#section');
  for(const invalid of [null,[],{sources:{feynman:{url:'javascript:alert(1)'}}}]) {
    writeFileSync(join(dir,'reflection-hints.json'),JSON.stringify(invalid));
    assert.equal(readReflectionHints(dir).sources.feynman.url,'https://example.com/template#section');
  }
});
