import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import net from 'node:net';
import http from 'node:http';
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {createInboxStore} from '../lib/inbox.mjs';
import {createWritingStore} from '../lib/writing.mjs';
async function port(){const s=net.createServer();s.listen(0,'127.0.0.1');await once(s,'listening');const p=s.address().port;await new Promise(r=>s.close(r));return p;}
const remoteGet=(url,headers)=>new Promise((resolve,reject)=>{const request=http.get(url,{headers},response=>{const chunks=[];response.on('data',chunk=>chunks.push(chunk));response.on('end',()=>resolve({status:response.statusCode,text:Buffer.concat(chunks).toString()}));});request.on('error',reject);});
test('Inbox HTTP supports native offline commands and authenticated range playback',async t=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'iw-inbox-api-')),ownerPort=await port(),viewerPort=await port();
  const writing=createWritingStore(path.join(directory,'writing.json')),inbox=createInboxStore(path.join(directory,'inbox.json'),{writing});
  const voice=inbox.receive('42',{update_id:1,message:{message_id:1,date:1792021200,chat:{id:88,type:'private'},from:{id:88},voice:{file_id:'V',duration:4}}});inbox.saveAudio(voice.id,Buffer.from('OggShello world'));
  const token='123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghi';fs.writeFileSync(path.join(directory,'telegram-bot.json'),JSON.stringify({token,botId:'42',enabled:false,ownerId:'88',username:'iw_capture_bot'}));
  const remote='https://desktop.example.ts.net';fs.writeFileSync(path.join(directory,'remote-access.json'),JSON.stringify({version:1,url:remote,allowedLogin:'owner@example.test',access:'read-write'}));
  const child=spawn(process.execPath,['server.mjs'],{cwd:path.resolve(import.meta.dirname,'..'),env:{...process.env,DASHBOARD_DATA_DIR:directory,DASHBOARD_PORT:String(ownerPort),DASHBOARD_VIEWER_PORT:String(viewerPort)},windowsHide:true,stdio:'ignore'});
  t.after(async()=>{if(child.exitCode===null){const ended=once(child,'exit');child.kill();await ended;}fs.rmSync(directory,{recursive:true,force:true});});
  const origin=`http://127.0.0.1:${ownerPort}`;
  for(let i=0;i<100;i++){try{if((await fetch(origin+'/api/health')).ok)break;}catch{}if(i===99)throw new Error('Server did not start');await delay(50);}
  const post=async(route,body)=>{const r=await fetch(origin+route,{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body:JSON.stringify(body)});return {status:r.status,body:await r.json()};};
  const status=await(await fetch(origin+'/api/telegram')).json();assert.equal(JSON.stringify(status).includes(token),false);assert.equal(status.paired,true);
  const deviceId=randomUUID(),context=await post('/api/offline/connect',{deviceId});
  const command={requestId:randomUUID(),deviceId,serverId:context.body.serverId,module:'inbox',action:'convert',expectedUpdatedAt:voice.updatedAt,input:{id:voice.id,title:'Идея на ходу',transcript:'Суть голоса',notes:'Уточнить завтра'}};
  const saved=await post('/api/native/command',command);assert.equal(saved.status,200);assert.equal(saved.body.inbox.entries[0].status,'reviewed');assert.equal(saved.body.writing.counts.drafts,1);
  assert.equal((await post('/api/native/command',command)).body.duplicate,true);
  assert.equal((await post('/api/native/command',{...command,deviceId:randomUUID(),requestId:randomUUID()})).status,409);
  const audio='/api/inbox/'+voice.id+'/audio',range=await fetch(origin+audio,{headers:{Range:'bytes=0-3'}});assert.equal(range.status,206);assert.equal(await range.text(),'OggS');assert.equal(range.headers.get('Content-Range'),'bytes 0-3/15');
  const headers={Host:'desktop.example.ts.net','Tailscale-User-Login':'owner@example.test',Origin:remote,Range:'bytes=4-8'};
  const proxy=await remoteGet(`http://127.0.0.1:${viewerPort}`+audio,headers);assert.equal(proxy.status,206);assert.equal(proxy.text,'hello');
  const denied=await remoteGet(`http://127.0.0.1:${viewerPort}`+audio,{...headers,'Tailscale-User-Login':'other@example.test'});assert.equal(denied.status,403);
  assert.equal((await fetch(origin+'/api/telegram',{method:'POST',headers:{Origin:'https://other.example','Content-Type':'application/json'},body:JSON.stringify({action:'pause'})})).status,403);
});
