import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createTransferManifest,verifyTransfer} from '../scripts/verify-transfer.mjs';
import {readHosting} from '../lib/hosting.mjs';
import {movedServer} from '../lib/server-location.mjs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

function fixture() {
  const root=mkdtempSync(path.join(tmpdir(),'iw-transfer-'));
  mkdirSync(path.join(root,'data','inbox-audio'),{recursive:true});
  writeFileSync(path.join(root,'data','dashboard.json'),JSON.stringify({offlineSync:{serverId:'same-owner-server'}}));
  writeFileSync(path.join(root,'data','writing.json'),JSON.stringify({instanceId:'same-writing-archive',entries:[{title:'  Заметка · 思考  ',text:'Первая\nВторая'}]}));
  writeFileSync(path.join(root,'data','inbox-audio','sample.ogg'),Buffer.from([0,10,255,128]));
  return root;
}
const save=(root,manifest)=>writeFileSync(path.join(root,'transfer-manifest.json'),JSON.stringify(manifest));

test('Перенос сохраняет байты заметок, аудио и идентификаторы архива',()=>{
  const root=fixture();
  const manifest=createTransferManifest(root,{final:true});save(root,manifest);
  const before=readFileSync(path.join(root,'data','writing.json'));
  const result=verifyTransfer(root,{requireFinal:true});
  assert.equal(result.files,3);assert.equal(result.identity.serverId,'same-owner-server');
  assert.equal(result.identity.writingInstanceId,'same-writing-archive');
  assert.deepEqual(readFileSync(path.join(root,'data','writing.json')),before);
  writeFileSync(path.join(root,'data','inbox-audio','sample.ogg'),Buffer.from([0,10,254,128]));
  assert.throws(()=>verifyTransfer(root),/checksum/);
});
test('Рабочий снимок не выдаётся за финальный перенос; лишние файлы обнаруживаются',()=>{
  const root=fixture();save(root,createTransferManifest(root));
  assert.throws(()=>verifyTransfer(root,{requireFinal:true}),/live preview/);
  writeFileSync(path.join(root,'extra.json'),'{}');
  assert.throws(()=>verifyTransfer(root),/Unlisted/);
});
test('Пути за пределы комплекта, ключи подписи и дубли не принимаются',()=>{
  const root=fixture();const original=createTransferManifest(root,{final:true});
  for(const invalid of ['../data/dashboard.json','C:/data/dashboard.json','data\\dashboard.json']) {
    const changed=structuredClone(original);changed.files[0].path=invalid;save(root,changed);
    assert.throws(()=>verifyTransfer(root),/Invalid transfer path/);
  }
  const duplicate=structuredClone(original);duplicate.files.push(duplicate.files[0]);save(root,duplicate);
  assert.throws(()=>verifyTransfer(root),/Duplicate/);
  mkdirSync(path.join(root,'data','native-signing'));
  writeFileSync(path.join(root,'data','native-signing','release.jks'),'private-key');
  assert.throws(()=>createTransferManifest(root),/Signing keys/);
});
test('Изменённый идентификатор даже с обновлённым хешем обнаруживается',()=>{
  const root=fixture();const manifest=createTransferManifest(root,{final:true});
  const file=path.join(root,'data','dashboard.json');
  const bytes=Buffer.from(JSON.stringify({offlineSync:{serverId:'new-empty-server'}}));writeFileSync(file,bytes);
  const entry=manifest.files.find(f=>f.path==='data/dashboard.json');
  entry.sha256=createHash('sha256').update(bytes).digest('hex');entry.size=bytes.length;save(root,manifest);
  assert.throws(()=>verifyTransfer(root),/identity changed/);
});
test('DigitalOcean означает работу без ПК; прежний конфиг остаётся совместим',()=>{
  const root=fixture(),file=path.join(root,'data','hosting.json');
  assert.deepEqual(readHosting(file),{provider:'computer',requiresComputer:true,explicit:false});
  writeFileSync(file,JSON.stringify({version:1,provider:'computer'}));assert.equal(readHosting(file).requiresComputer,true);
  writeFileSync(file,JSON.stringify({version:1,provider:'digitalocean'}));assert.deepEqual(readHosting(file),{provider:'digitalocean',requiresComputer:false,explicit:true});
  writeFileSync(file,JSON.stringify({version:1,provider:'public'}));assert.throws(()=>readHosting(file),/хостинга/);
});

test('Адрес переезда сохраняет только закрытый HTTPS и не допускает подмену',()=>{
  const root=fixture(),file=path.join(root,'data','server-moved.json');
  assert.equal(movedServer(file),null);
  writeFileSync(file,JSON.stringify({version:1,url:'https://iw-server.owner-net.ts.net'}));
  assert.equal(movedServer(file),'https://iw-server.owner-net.ts.net');
  for(const url of ['http://iw-server.owner-net.ts.net','https://public.example.com','https://iw-server.owner-net.ts.net/anything','https://secret@iw-server.owner-net.ts.net']) {
    writeFileSync(file,JSON.stringify({version:1,url}));assert.throws(()=>movedServer(file));
  }
  writeFileSync(file,JSON.stringify({version:1,url:'https://iw-server.owner-net.ts.net'}));
  const bytes=readFileSync(path.join(root,'data','writing.json'));
  const child=spawnSync(process.execPath,[fileURLToPath(new URL('../server.mjs',import.meta.url))],{encoding:'utf8',env:{...process.env,DASHBOARD_DATA_DIR:path.join(root,'data')}});
  assert.notEqual(child.status,0);assert.match(child.stderr,/локальная запись отключена/);
  assert.deepEqual(readFileSync(path.join(root,'data','writing.json')),bytes);
});
