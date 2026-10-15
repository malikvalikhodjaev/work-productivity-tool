import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {randomUUID,createHash} from 'node:crypto';
import {createInboxStore} from '../lib/inbox.mjs';
import {createWritingStore} from '../lib/writing.mjs';
import {createTelegramBot} from '../lib/telegram-bot.mjs';
import {replaceFile} from '../lib/atomic-file.mjs';
import {backupData} from '../lib/backup.mjs';

const token='123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghi';
const update=(id,text='Мысль на ходу · 中文',extra={})=>({update_id:id,message:{message_id:19,date:1792021200,chat:{id:88,type:'private'},from:{id:88,is_bot:false},text,...extra}});
function fixture(t,options={}){const directory=fs.mkdtempSync(path.join(os.tmpdir(),'iw-inbox-')),file=path.join(directory,'inbox.json');t.after(()=>fs.rmSync(directory,{recursive:true,force:true}));const writing=createWritingStore(path.join(directory,'writing.json'));const inbox=createInboxStore(file,{writing,...options});return {directory,file,inbox,writing,command:(item,action='save',input={})=>({requestId:randomUUID(),action,expectedUpdatedAt:item.updatedAt,input:{id:item.id,...input}})};}

test('Telegram text is retained exactly; repeated delivery and restart do not duplicate it',t=>{
  const f=fixture(t),original=update(1,'  中文\n<script>мысль</script>  '),item=f.inbox.receive('42',original);
  f.inbox.receive('42',original);assert.equal(f.inbox.view().entries.length,1);assert.equal(f.inbox.cursor('42'),2);
  const reopened=createInboxStore(f.file,{writing:f.writing});assert.deepEqual(reopened.exportData().entries[0].originals,[original]);assert.equal(reopened.view().entries[0].sourceText,original.message.text);assert.equal(item.sourceKey,undefined);
  const changed={update_id:2,edited_message:{...original.message,text:'Уточнённый исходник'}};reopened.receive('42',changed);assert.equal(reopened.view().entries.length,1);assert.equal(reopened.exportData().entries[0].originals[0].message.text,original.message.text);
});
test('Review has history and protects concurrent edits; Telegram changes preserve my review',t=>{
  const f=fixture(t),item=f.inbox.receive('42',update(1));const command=f.command(item,'save',{title:'Идея',notes:'Мои размышления',transcript:'Суть'});
  const saved=f.inbox.mutate(command).item;assert.equal(f.inbox.mutate(command).duplicate,true);
  assert.throws(()=>f.inbox.mutate(f.command(item,'save',{notes:'Устаревшая версия'})),e=>e.status===409);
  f.inbox.receive('42',{update_id:2,edited_message:{...update(1).message,text:'Изменение источника'}});
  assert.equal(f.inbox.view().entries[0].notes,'Мои размышления');assert.equal(saved.title,'Идея');assert.equal(f.inbox.exportData().entries[0].revisions.length,1);
});
test('Draft conversion survives a failure between files, with no duplicate or lost review',t=>{
  let failFinal=false;
  const storage={...fs,replaceFile:(from,to)=>{const value=JSON.parse(fs.readFileSync(from,'utf8'));if(failFinal&&value.entries?.some(e=>e.writingId)){const error=new Error('Disk failed');error.code='EIO';throw error;}replaceFile(from,to);}};
  const f=fixture(t,{storage}),item=f.inbox.receive('42',update(1));const command=f.command(item,'convert',{title:'Эссе',notes:'Разобрать спокойно'});
  failFinal=true;assert.throws(()=>f.inbox.mutate(command),/Disk failed/);assert.equal(f.writing.view().counts.drafts,1);assert.equal(f.inbox.view().entries[0].writingId,null);
  assert.throws(()=>f.inbox.mutate({...command,input:{...command.input,notes:'Подмена'}}),e=>e.status===409);
  failFinal=false;const reopened=createInboxStore(f.file,{writing:f.writing});const result=reopened.mutate(command);assert.equal(result.item.status,'reviewed');assert.equal(f.writing.view().counts.drafts,1);assert.equal(reopened.mutate(command).duplicate,true);assert.equal(result.item.notes,'Разобрать спокойно');
  const doc=f.writing.get(result.item.writingId);assert.equal(doc.document.ops[0].insert,'Мысль на ходу · 中文\n\nРазобрать спокойно\n');assert.equal(doc.status,'draft');
});
test('Voice original, bytes and hash survive restart; downloading does not invalidate a review',t=>{
  const f=fixture(t),voice=update(1,undefined,{text:undefined,voice:{file_id:'voice-A',duration:12,mime_type:'audio/ogg',file_size:8}}),item=f.inbox.receive('42',voice),bytes=Buffer.from('OggSvoice');
  f.inbox.saveAudio(item.id,bytes);const reopened=createInboxStore(f.file,{writing:f.writing}),audio=reopened.audioFile(item.id);assert.deepEqual(fs.readFileSync(audio.path),bytes);assert.equal(path.basename(audio.path),createHash('sha256').update(bytes).digest('hex')+'.ogg');
  assert.equal(reopened.mutate(f.command(item,'save',{transcript:'Что я хочу исправить?'})).item.transcript,'Что я хочу исправить?');
  const backup=backupData(f.directory);const saved=path.join(f.directory,'backups',backup.directory,'inbox-audio',path.basename(audio.path));assert.deepEqual(fs.readFileSync(saved),bytes);assert.equal(reopened.view().entries[0].audio.fileId,undefined);
});
test('Oversized audio leaves the original in the inbox; archiving is reversible',t=>{
  const f=fixture(t),item=f.inbox.receive('42',update(1,undefined,{text:undefined,voice:{file_id:'huge',duration:900,file_size:30*1024*1024}}));assert.equal(item.audio.status,'too-large');assert.equal(f.inbox.pendingAudio('42').length,0);
  const archived=f.inbox.mutate(f.command(item,'archive')).item;const restored=f.inbox.mutate(f.command(archived,'reopen')).item;assert.equal(restored.status,'new');assert.equal(f.inbox.exportData().entries[0].originals.length,1);
});
test('Bot pairing accepts only the secret link and private owner messages; status hides the token',async t=>{
  const f=fixture(t);let queue=[];const methods=[];
  const fetcher=async(url,options)=>{const method=url.split('/').at(-1);methods.push(method);const result=method==='getMe'?{id:42,username:'iw_capture_bot'}:method==='getWebhookInfo'?{url:''}:method==='getUpdates'?queue.splice(0):true;return new Response(JSON.stringify({ok:true,result}),{status:200});};
  const file=path.join(f.directory,'telegram-bot.json'),bot=createTelegramBot({file,inbox:f.inbox,fetcher,autoStart:false});t.after(()=>bot.stop());
  const status=await bot.configure({token});assert.equal(JSON.stringify(status).includes(token),false);const code=new URL(status.pairingUrl).searchParams.get('start');
  queue=[update(1,'/start incorrect')];await bot.poll();assert.equal(bot.status().paired,false);
  queue=[update(2,'/start '+code)];await bot.poll();assert.equal(bot.status().paired,true);assert.equal(bot.status().pairingUrl,null);
  queue=[update(3,'От чужого',{chat:{id:99,type:'private'},from:{id:99,is_bot:false}}),update(4,'В группе',{chat:{id:-9,type:'group'}}),update(5,'Моя идея')];await bot.poll();assert.equal(f.inbox.view().entries.length,1);assert.equal(f.inbox.view().entries[0].sourceText,'Моя идея');assert.equal(f.inbox.cursor('42'),6);assert.ok(methods.includes('sendMessage'));
  const reopened=createTelegramBot({file,inbox:f.inbox,fetcher,autoStart:false});assert.equal(reopened.status().paired,true);reopened.stop();
});
test('Audio download is retried after network failure; offset advances only after saving the source',async t=>{
  const f=fixture(t);let queue=[],failAudio=true;const bytes=Buffer.from('OggS1234');const file=path.join(f.directory,'telegram-bot.json');fs.writeFileSync(file,JSON.stringify({version:1,token,botId:'42',username:'iw_capture_bot',ownerId:'88',enabled:true}));
  const fetcher=async(url)=>{if(url.includes('/file/bot')){if(failAudio)throw new Error('Network disconnected');return new Response(bytes);}const method=url.split('/').at(-1),result=method==='getUpdates'?queue.splice(0):method==='getFile'?{file_path:'voice/file.ogg',file_size:bytes.length}:true;return new Response(JSON.stringify({ok:true,result}));};
  const bot=createTelegramBot({file,inbox:f.inbox,fetcher,autoStart:false});t.after(()=>bot.stop());queue=[update(1,undefined,{text:undefined,voice:{file_id:'A',duration:4}})];await bot.poll();assert.equal(f.inbox.cursor('42'),2);assert.equal(f.inbox.view().entries[0].audio.status,'pending');failAudio=false;await bot.poll();assert.equal(f.inbox.view().entries[0].audio.status,'ready');assert.equal(f.inbox.view().entries.length,1);
});
