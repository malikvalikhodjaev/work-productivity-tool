import { readFileSync,writeFileSync,existsSync } from 'node:fs';
import { resolve,join } from 'node:path';
import { exportSnapshot } from './export-cloud-snapshot.mjs';
import { replaceFile } from '../lib/atomic-file.mjs';

const [dataDir,siteUrl]=process.argv.slice(2);
if(!dataDir||!siteUrl)throw new Error('Укажи каталог данных и HTTPS-адрес Site. Токен передаётся только через stdin.');
const url=new URL(siteUrl);
if(url.protocol!=='https:'||!url.hostname.endsWith('.chatgpt.site')||url.username||url.password||url.pathname!=='/'||url.search||url.hash)throw new Error('Неверный HTTPS-адрес Site.');
const credential=await new Promise((resolve,reject)=>{
  let value='';const terminal=process.stdin.isTTY;
  const finish=error=>{
    process.stdin.removeListener('data',onData);process.stdin.removeListener('end',onEnd);
    if(terminal)process.stdin.setRawMode(false);process.stdin.pause();
    error?reject(error):resolve(value.trim());
  };
  const onData=chunk=>{value+=chunk;if(value.includes('\u0003'))finish(new Error('Загрузка отменена.'));else if(value.length>65536)finish(new Error('Недопустимый размер служебного доступа.'));else if(/[\r\n]/.test(value))finish();};
  const onEnd=()=>finish();
  if(terminal)process.stdin.setRawMode(true);
  console.log('Ready for Site service credential on stdin (input is hidden).');
  process.stdin.setEncoding('utf8');process.stdin.on('data',onData);process.stdin.once('end',onEnd);process.stdin.resume();
});
if(typeof credential!=='string'||!credential||/[\r\n\0]/.test(credential))throw new Error('Нет служебного доступа.');
const headers={'OAI-Sites-Authorization':`Bearer ${credential}`};
const status=await fetch(`${url.origin}/api/mobile-access`,{headers,redirect:'error'});
if(!status.ok)throw new Error(`Не удалось проверить Site: HTTP ${status.status}.`);
const current=await status.json();if(current.provider!=='sites'||current.access!=='read-only')throw new Error('Неожиданная конфигурация Site.');
const exported=exportSnapshot(dataDir);
const response=await fetch(`${url.origin}/api/cloud/snapshot`,{method:'POST',headers:{...headers,'Content-Type':'application/json'},body:JSON.stringify({...exported,expectedSha:current.sha}),redirect:'error'});
if(!response.ok)throw new Error(`Не удалось загрузить снимок: HTTP ${response.status}. Предыдущий снимок сохранён.`);
const result=await response.json();if(!result.ok)throw new Error('Загрузка не подтверждена.');
const healthResponse=await fetch(`${url.origin}/api/health`,{headers,redirect:'error'});
const health=await healthResponse.json();
if(!healthResponse.ok||!health.snapshotReady||health.capturedAt!==result.capturedAt)throw new Error('Site не подтвердил активный снимок.');
const referencesResponse=await fetch(`${url.origin}/api/references`,{headers,redirect:'error'});
const references=await referencesResponse.json(),sourceReferences=JSON.parse(exported.snapshot.files['references.json']);
if(!referencesResponse.ok||JSON.stringify(references.entries)!==JSON.stringify(sourceReferences.entries))throw new Error('Источники Site не совпадают со снимком.');
const tablesResponse=await fetch(`${url.origin}/api/imported-data`,{headers,redirect:'error'}),tables=await tablesResponse.json();
if(!tablesResponse.ok)throw new Error('Импортированные таблицы недоступны.');
for(const [file,field] of [['imports/coda-snapshot.json','snapshot'],['imports/alpha-reference.json','reference']]){
  if(exported.snapshot.files[file]){
    const {available,...actual}=tables[field];
    if(!available||JSON.stringify(actual)!==JSON.stringify(JSON.parse(exported.snapshot.files[file])))throw new Error('Импортированная таблица не совпадает со снимком.');
  }
}
for(const item of exported.snapshot.attachments){
  const reference=sourceReferences.entries.find(entry=>`reference-assets/${entry.attachment}`===item.path);
  const attachmentResponse=await fetch(`${url.origin}/api/references/${reference.id}/attachment`,{headers,redirect:'error'});
  const value=await attachmentResponse.arrayBuffer();
  const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',value))).map(byte=>byte.toString(16).padStart(2,'0')).join('');
  if(!attachmentResponse.ok||hash!==item.sha256||attachmentResponse.headers.get('cache-control')!=='no-store')throw new Error('Вложение не прошло проверку.');
}
for(const method of ['POST','PUT','PATCH','DELETE']){
  const blocked=await fetch(`${url.origin}/api/references`,{method,headers,redirect:'error'});
  if(blocked.status!==403)throw new Error('Запрет изменения не подтверждён.');
}
const anonymous=await fetch(`${url.origin}/api/references`,{redirect:'manual'});
if(anonymous.ok&&anonymous.headers.get('content-type')?.includes('application/json'))throw new Error('Анонимный JSON доступ не должен быть разрешён.');
const file=join(resolve(dataDir),'cloud-view.json');
if(existsSync(file)){
  const previous=JSON.parse(readFileSync(file,'utf8'));
  if(previous.url!==url.origin)throw new Error('Снимок загружен, но локальная ссылка не заменена: выбран другой Site.');
}
writeFileSync(`${file}.tmp`,JSON.stringify({provider:'sites',url:url.origin,capturedAt:result.capturedAt,sha:result.sha},null,2)+'\n');replaceFile(`${file}.tmp`,file);
console.log(JSON.stringify({ok:true,verified:true,url:url.origin,capturedAt:result.capturedAt,files:result.files,attachments:result.attachments,sha:result.sha,anonymousStatus:anonymous.status,mutationMethodsBlocked:4}));
