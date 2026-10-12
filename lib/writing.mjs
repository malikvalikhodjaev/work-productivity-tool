import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { randomUUID, createHash } from 'node:crypto';
import { replaceFile } from './atomic-file.mjs';
import { today, validDate } from './store.mjs';

const uuid = value => typeof value === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(value);
const fail = message => { throw new Error(message); };
const conflict = message => { const error=new Error(message); error.status=409; throw error; };
export function writingDocument(input) {
  if (!input || !Array.isArray(input.ops) || !input.ops.length || input.ops.length>10000) fail('Некорректный документ редактора.');
  let length=0;
  const ops=input.ops.map(op=>{
    if (!op || typeof op.insert!=='string' || !op.insert.length || Object.keys(op).some(k=>!['insert','attributes'].includes(k))) fail('Поддерживается текст с форматированием.');
    length+=op.insert.length;
    const result={insert:op.insert};
    if(op.attributes!==undefined) {
      if(!op.attributes||typeof op.attributes!=='object'||Array.isArray(op.attributes)) fail('Некорректное форматирование.');
      const attributes={};
      for(const [key,value] of Object.entries(op.attributes)) {
        if(['bold','italic','underline','strike','blockquote','code'].includes(key)&&value===true) attributes[key]=value;
        else if(key==='header'&&Number.isInteger(value)&&value>=1&&value<=4) attributes[key]=value;
        else if(key==='list'&&['ordered','bullet'].includes(value)) attributes[key]=value;
        else if(key==='indent'&&Number.isInteger(value)&&value>=1&&value<=8) attributes[key]=value;
        else if(key==='align'&&['center','right','justify'].includes(value)) attributes[key]=value;
        else if(key==='link'&&typeof value==='string'&&value.length<=3000) {
          let url; try {url=new URL(value);} catch{fail('Для ссылки нужен полный адрес http:// или https://.');}
          if(!['http:','https:','mailto:'].includes(url.protocol)||url.username||url.password) fail('Эта ссылка не поддерживается.');
          attributes[key]=value;
        } else fail('Неподдерживаемый формат текста: '+key);
      }
      if(Object.keys(attributes).length) result.attributes=attributes;
    }
    return result;
  });
  if(length>200000) fail('Запись длиннее 200 000 символов. Сохрани её отдельными эссе.');
  if(!ops.at(-1).insert.endsWith('\n')) fail('Документ должен завершаться переводом строки.');
  return {ops};
}
const textOf=document=>document.ops.map(op=>op.insert).join('');
const snapshot=p=>({title:p.title,date:p.date,status:p.status,document:structuredClone(p.document),publishedAt:p.publishedAt,trashedAt:p.trashedAt,revision:p.revision,updatedAt:p.updatedAt});
const native={existsSync,mkdirSync,readFileSync,writeFileSync,replaceFile};
export function createWritingStore(file,{storage=native,now=()=>Date.now(),getToday=today}={}) {
  const io=storage; io.mkdirSync(dirname(file),{recursive:true});
  let data=io.existsSync(file)?JSON.parse(io.readFileSync(file,'utf8')):{version:1,instanceId:randomUUID(),entries:[]};
  if(data.version!==1||!uuid(data.instanceId)||!Array.isArray(data.entries)) fail('Неподдерживаемый архив записей. Исходник сохранён.');
  for(const p of data.entries) {if(!uuid(p.id)||!['draft','published'].includes(p.status)||!validDate(p.date)||!Number.isInteger(p.revision)||p.revision<1||!Array.isArray(p.revisions)) fail('Повреждённая запись. Исходник сохранён.'); writingDocument(p.document);}
  if(new Set(data.entries.map(p=>p.id)).size!==data.entries.length) fail('Повторяющийся ID записи. Исходник сохранён.');
  function persist(next) {io.writeFileSync(file+'.tmp',JSON.stringify(next,null,2)+'\n','utf8');io.replaceFile(file+'.tmp',file);data=next;}
  if(!io.existsSync(file)) persist(data);
  function summary(p) {const text=textOf(p.document).trim();return {id:p.id,title:p.title,date:p.date,status:p.status,publishedAt:p.publishedAt,trashedAt:p.trashedAt,revision:p.revision,createdAt:p.createdAt,updatedAt:p.updatedAt,words:text?text.split(/\s+/u).length:0,excerpt:text.replace(/\s+/gu,' ').slice(0,170),edits:p.revisions.length};}
  function view(query='') {
    if(typeof query!=='string'||query.length>300) fail('Поиск: не больше 300 символов.');
    const counts=new Map();
    for(const p of data.entries.filter(p=>p.status==='published'&&!p.trashedAt)){const month=p.date.slice(0,7);counts.set(month,(counts.get(month)??0)+1);}
    const q=query.toLocaleLowerCase('ru');
    return {version:1,instanceId:data.instanceId,today:getToday(),timezone:'Asia/Tashkent',
      entries:data.entries.filter(p=>!q||(p.title+'\n'+textOf(p.document)).toLocaleLowerCase('ru').includes(q)).map(summary).sort((a,b)=>b.date.localeCompare(a.date)||b.createdAt.localeCompare(a.createdAt)),
      months:[...counts].sort((a,b)=>b[0].localeCompare(a[0])).map(([month,count])=>({month,count})),
      counts:{published:data.entries.filter(p=>p.status==='published'&&!p.trashedAt).length,drafts:data.entries.filter(p=>p.status==='draft'&&!p.trashedAt).length,trash:data.entries.filter(p=>p.trashedAt).length}};
  }
  function get(id) {const p=data.entries.find(p=>p.id===id);if(!p)fail('Запись не найдена.');return structuredClone(p);}
  function save(input) {
    if(!input||!uuid(input.id)||!uuid(input.requestId)||!Number.isInteger(input.expectedRevision)||input.expectedRevision<0) fail('Нужны ID записи, запроса и версия.');
    if(input.instanceId!==data.instanceId) conflict('Это другой архив. Локальный текст сохранён; подключи прежний сервер.');
    if(!['save','trash','restore'].includes(input.action)) fail('Неизвестное действие записи.');
    const before=data.entries.find(p=>p.id===input.id),signature=createHash('sha256').update(JSON.stringify(Object.fromEntries(Object.entries(input).filter(([k])=>!['requestId','expectedRevision'].includes(k))))).digest('hex');
    const receipt=before?.requests?.find(r=>r.id===input.requestId);
    if(receipt){if(receipt.signature!==signature||receipt.revision!==before.revision)conflict('Запись уже изменена после этого запроса. Локальный текст сохранён.');return {entry:get(before.id),duplicate:true};}
    if(input.expectedRevision!==(before?.revision??0)) conflict('Запись изменена в другой вкладке или на устройстве. Локальный текст сохранён.');
    let fields;
    if(input.action==='save') {
      if(before?.trashedAt) conflict('Запись находится в корзине. Сначала восстанови её.');
      if(typeof input.title!=='string'||input.title.length>300) fail('Тема: не больше 300 символов.');
      if(!validDate(input.date)||input.date>getToday()) fail('Дата записи: сегодня или прошедший день.');
      if(!['draft','published'].includes(input.status)) fail('Выбери черновик или публикацию.');
      const document=writingDocument(input.document),title=input.title.trim();
      if(input.status==='published'&&(!title||!textOf(document).trim())) fail('Для публикации нужны тема и текст.');
      fields={title,date:input.date,status:input.status,document,trashedAt:null};
    } else {
      if(!before)fail('Запись не найдена.'); fields=snapshot(before);
      if(input.action==='trash'&&before.trashedAt)fail('Запись уже в корзине.');
      if(input.action==='restore'&&!before.trashedAt)fail('Запись уже восстановлена.');
    }
    if(before&&input.action==='save'&&['title','date','status','document'].every(k=>JSON.stringify(before[k])===JSON.stringify(fields[k]))) return {entry:get(before.id),duplicate:true};
    const stamp=new Date(Math.max(now(),before?Date.parse(before.updatedAt)+1:0)).toISOString();
    const entry={...before,id:input.id,...fields,createdAt:before?.createdAt??stamp,updatedAt:stamp,revision:(before?.revision??0)+1,
      publishedAt:fields.status==='published'?(before?.publishedAt??stamp):before?.publishedAt??null,
      trashedAt:input.action==='trash'?stamp:input.action==='restore'?null:fields.trashedAt,
      revisions:before?[...before.revisions,{...snapshot(before),action:input.action,replacedAt:stamp}]:[],
      requests:[...(before?.requests??[]),{id:input.requestId,signature,revision:(before?.revision??0)+1}].slice(-128)};
    persist({...data,entries:before?data.entries.map(p=>p.id===entry.id?entry:p):[...data.entries,entry]});
    return {entry:get(entry.id),duplicate:false};
  }
  const exportData=()=>({format:'indicators-work-writing',version:1,exportedAt:new Date(now()).toISOString(),instanceId:data.instanceId,entries:structuredClone(data.entries)});
  return {view,get,save,exportData,context:()=>({instanceId:data.instanceId,today:getToday()})};
}
