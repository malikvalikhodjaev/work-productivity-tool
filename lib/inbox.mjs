import * as fs from 'node:fs';
import path from 'node:path';
import {createHash, randomUUID} from 'node:crypto';
import {replaceFile} from './atomic-file.mjs';
import {assertNativeBase, nativeCommandGuard, nativeCommandSignature, nativeId} from './native-commands.mjs';
import {today} from './store.mjs';

export const INBOX_AUDIO_LIMIT = 20 * 1024 * 1024;
const fail = (message, status=400) => {const error=new Error(message);error.status=status;throw error;};
const audioTypes = new Map([['audio/ogg','.ogg'],['audio/opus','.ogg'],['audio/mpeg','.mp3'],['audio/mp4','.m4a'],['audio/x-m4a','.m4a'],['audio/wav','.wav']]);
export function telegramTitle(sentAt) {
  const date=new Date(Date.parse(sentAt)+5*3600000),pad=n=>String(n).padStart(2,'0');
  return `telegram-note (${pad(date.getUTCDate())}.${pad(date.getUTCMonth()+1)}.${date.getUTCFullYear()} ${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())})`;
}
export function createInboxStore(file, {writing, now=()=>Date.now(), storage={...fs,replaceFile}}={}) {
  const io=storage, folder=path.join(path.dirname(file),'inbox-audio');
  io.mkdirSync(path.dirname(file),{recursive:true});
  let data=io.existsSync(file)?JSON.parse(io.readFileSync(file,'utf8')):{version:1,entries:[],cursors:{}};
  if(data.version!==1 || !Array.isArray(data.entries) || !data.cursors || data.entries.some(e=>!nativeId(e.id)||!nativeId(e.noteId)||!Array.isArray(e.originals))) fail('Повреждён архив входящих. Исходник сохранён.');
  const guard=nativeCommandGuard(()=>data);
  function persist(next, receipt=true) {
    next=receipt?guard.prepare(next):next;
    io.writeFileSync(file+'.tmp',JSON.stringify(next,null,2)+'\n','utf8');
    io.replaceFile(file+'.tmp',file);data=next;
  }
  if(!io.existsSync(file)) persist(data);
  const stamp = entry=>new Date(Math.max(now(),Date.parse(entry?.updatedAt??'1970-01-01')+1)).toISOString();
  const find = id=>{const item=data.entries.find(e=>e.id===id);if(!item)fail('Входящая заметка не найдена.',404);return item;};
  const publicItem = item=>{
    const {originals,sourceKey,noteRequestId,conversion,...value}=item;
    const generated=(item.sourceText.trim().split('\n')[0].slice(0,180)||'Голосовая мысль');
    const legacyTitle=item.body===undefined&&item.title===generated&&!item.revisions.some(r=>r.title!==item.title);
    return {...structuredClone(value),favorite:item.favorite===true,title:legacyTitle?telegramTitle(item.sentAt):item.title,body:item.body??item.sourceText,originalCount:originals.length,audio:item.audio?{status:item.audio.status,mime:item.audio.mime,duration:item.audio.duration,size:item.audio.size,error:item.audio.error??null,url:item.audio.status==='ready'?`/api/inbox/${item.id}/audio`:null}:null};
  };
  function view() {
    const entries=data.entries.map(publicItem).sort((a,b)=>b.receivedAt.localeCompare(a.receivedAt));
    return {version:1,entries,counts:{new:entries.filter(e=>e.status==='new').length,reviewed:entries.filter(e=>e.status==='reviewed').length,archived:entries.filter(e=>e.status==='archived').length}};
  }
  function receive(botId, update) {
    if(!Number.isSafeInteger(update.update_id)||update.update_id<0)fail('Неверный update_id Telegram.');
    const message=update.message??update.edited_message;
    const cursors={...data.cursors,[botId]:Math.max(data.cursors[botId]??0,update.update_id+1)};
    if(!message || message.chat?.type!=='private' || !Number.isSafeInteger(message.message_id)) {persist({...data,cursors});return null;}
    const sourceKey=`${botId}:${message.chat.id}:${message.message_id}`;
    const before=data.entries.find(e=>e.sourceKey===sourceKey);
    if(before?.originals.some(v=>v.update_id===update.update_id)){persist({...data,cursors});return publicItem(before);}
    const media=message.voice??message.audio;
    if(typeof message.text!=='string'&&!media){persist({...data,cursors});return null;}
    const text=message.text??message.caption??'', created=stamp(before);
    let audio=before?.audio??null;
    if(media && (!audio || audio.fileId!==media.file_id)) {
      const mime=message.voice?'audio/ogg':media.mime_type??'audio/mpeg';
      audio={fileId:media.file_id,mime:audioTypes.has(mime)?mime:'audio/mpeg',duration:media.duration??null,size:media.file_size??null,status:(media.file_size??0)>INBOX_AUDIO_LIMIT?'too-large':'pending',error:(media.file_size??0)>INBOX_AUDIO_LIMIT?'Файл больше лимита Telegram Bot API — 20 MB.':null};
    }
    const sentAt=new Date((message.date??Math.floor(now()/1000))*1000).toISOString();
    const item={...before,id:before?.id??randomUUID(),noteId:before?.noteId??randomUUID(),noteRequestId:before?.noteRequestId??randomUUID(),sourceKey,botId:String(botId),kind:media?'voice':'text',sourceText:text,
      title:before?publicItem(before).title:telegramTitle(sentAt),body:before?.body===undefined||before.body===before.sourceText?text:before.body,transcript:before?.transcript??'',notes:before?.notes??'',status:before?.status??'new',writingId:before?.writingId??null,audio,
      sentAt,receivedAt:before?.receivedAt??created,updatedAt:created,
      originals:[...(before?.originals??[]),structuredClone(update)],revisions:before?.revisions??[]};
    persist({...data,cursors,entries:before?data.entries.map(e=>e.id===item.id?item:e):[...data.entries,item]});
    return publicItem(item);
  }
  function skip(botId, updateId){persist({...data,cursors:{...data.cursors,[botId]:Math.max(data.cursors[botId]??0,updateId+1)}});}
  function pendingAudio(botId){return data.entries.filter(e=>e.botId===String(botId)&&e.audio?.status==='pending').map(e=>({id:e.id,fileId:e.audio.fileId}));}
  function saveAudio(id, bytes) {
    const before=find(id);if(!before.audio)fail('Это текстовая заметка.');
    if(!Buffer.isBuffer(bytes)||bytes.length>INBOX_AUDIO_LIMIT)fail('Аудио больше 20 MB.');
    const hash=createHash('sha256').update(bytes).digest('hex'),name=hash+(audioTypes.get(before.audio.mime)??'.ogg');
    io.mkdirSync(folder,{recursive:true});const destination=path.join(folder,name);
    if(!io.existsSync(destination)){io.writeFileSync(destination+'.tmp',bytes);io.replaceFile(destination+'.tmp',destination);}
    if(createHash('sha256').update(io.readFileSync(destination)).digest('hex')!==hash)fail('Не удалось проверить сохранённое аудио.');
    const item={...before,audio:{...before.audio,status:'ready',size:bytes.length,file:name,sha256:hash,error:null}};
    // Downloading audio does not change the version of the user's review fields.
    persist({...data,entries:data.entries.map(e=>e.id===id?item:e)});return publicItem(item);
  }
  function audioError(id,message,permanent=false){const item=find(id);persist({...data,entries:data.entries.map(e=>e.id===id?{...item,audio:{...item.audio,status:permanent?'too-large':'pending',error:message}}:e)});}
  function audioFile(id) {
    const item=find(id);if(item.audio?.status!=='ready'||!/^[a-f0-9]{64}\.(ogg|mp3|m4a|wav)$/.test(item.audio.file))fail('Аудио ещё не загружено.',404);
    return {path:path.join(folder,item.audio.file),mime:item.audio.mime,size:item.audio.size};
  }
  function fields(input,before) {
    const values={title:input.title??publicItem(before).title,body:input.body??before.body??before.sourceText,transcript:input.transcript??before.transcript,notes:input.notes??before.notes};
    for(const [name,value] of Object.entries(values))if(typeof value!=='string'||value.length>(name==='title'?300:80000))fail(name==='title'?'Тема: до 300 знаков.':'Текст разбора: до 80 000 знаков.');
    if(input.favorite!==undefined&&typeof input.favorite!=='boolean')fail('Метка избранного: да или нет.');
    return {...values,favorite:input.favorite??before.favorite??false};
  }
  function mutate(command) {
    if(!['save','archive','reopen','convert'].includes(command.action)||!nativeId(command.input?.id))fail('Неизвестное действие входящих.');
    const result=guard.run(command,()=>{
      const before=find(command.input.id),review=fields(command.input,before);
      if(before.conversion && before.conversion.hash!==nativeCommandSignature(command)) fail('Создание черновика не завершено. Повтори исходную команду; разбор сохранён.',409);
      if(!before.conversion)assertNativeBase(before,command.expectedUpdatedAt);
      let writingId=before.writingId;
      if(command.action==='convert'&&!writingId) {
        if(!writing)fail('Редактор заметок не подключён.');
        const prepared=before.conversion??{requestId:command.requestId,hash:nativeCommandSignature(command),review,packet:{id:before.noteId,requestId:before.noteRequestId,instanceId:writing.context().instanceId,expectedRevision:0,action:'save',title:review.title,date:today(),status:'draft',document:{ops:[{insert:[review.body??before.sourceText,review.transcript,review.notes].filter(t=>t.trim()).join('\n\n')+'\n'}]}}};
        if(!before.conversion)persist({...data,entries:data.entries.map(e=>e.id===before.id?{...e,conversion:prepared}:e)},false);
        let article;try{article=writing.get(before.noteId);}catch(e){if(e.message!=='Запись не найдена.')throw e;}
        article??=writing.save(prepared.packet).entry;
        writingId=article.id;
        Object.assign(review,prepared.review);
      }
      const status=command.action==='archive'?'archived':command.action==='reopen'?'new':command.action==='convert'?'reviewed':before.status;
      const item={...find(before.id),...review,status,writingId,conversion:null,updatedAt:stamp(before),revisions:[...before.revisions,{title:before.title,body:before.body??before.sourceText,favorite:before.favorite===true,transcript:before.transcript,notes:before.notes,status:before.status,writingId:before.writingId,updatedAt:before.updatedAt}]};
      persist({...data,entries:data.entries.map(e=>e.id===item.id?item:e)});
    });
    return {...result,item:publicItem(find(command.input.id)),inbox:view(),...(command.action==='convert'?{writing:writing.view(),writingExport:writing.exportData()}: {})};
  }
  return {view,receive,skip,mutate,pendingAudio,saveAudio,audioError,audioFile,cursor:botId=>data.cursors[botId]??0,exportData:()=>structuredClone(data)};
}
