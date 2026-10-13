import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import net from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';

async function port(){const server=net.createServer();server.listen(0,'127.0.0.1');await once(server,'listening');const value=server.address().port;await new Promise(resolve=>server.close(resolve));return value;}
test('Native HTTP bridge validates identity, keeps receipts, and exposes daily norms without fabricating time',async t=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'iw-native-api-'));
  const ownerPort=await port(),viewerPort=await port();
  const child=spawn(process.execPath,['server.mjs'],{cwd:path.resolve(import.meta.dirname,'..'),env:{...process.env,DASHBOARD_DATA_DIR:directory,DASHBOARD_PORT:String(ownerPort),DASHBOARD_VIEWER_PORT:String(viewerPort)},windowsHide:true,stdio:'ignore'});
  t.after(async()=>{if(child.exitCode===null){const ended=once(child,'exit');child.kill();await ended;}fs.rmSync(directory,{recursive:true,force:true});});
  const origin=`http://127.0.0.1:${ownerPort}`;
  for(let i=0;i<100;i++){try{if((await fetch(`${origin}/api/health`)).ok)break;}catch{}if(i===99)throw new Error('QA server did not start');await delay(50);}
  const post=async(route,body)=>{const response=await fetch(origin+route,{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body:JSON.stringify(body)});return {status:response.status,body:await response.json()};};
  const deviceId=randomUUID();const connected=await post('/api/offline/connect',{deviceId});assert.equal(connected.status,200);
  const serverId=connected.body.serverId,caseId=randomUUID();
  const command={requestId:randomUUID(),deviceId,serverId,module:'workspace',action:'saveCase',expectedUpdatedAt:null,input:{clientId:caseId,title:'Важный разрыв · 问题',status:'active'}};
  const first=await post('/api/native/command',command);assert.equal(first.status,200);assert.equal(first.body.workspace.cases[0].id,caseId);assert.equal(first.body.workspace.nativeRequests,undefined);
  const retry=await post('/api/native/command',command);assert.equal(retry.body.duplicate,true);assert.equal(retry.body.workspace.cases.length,1);
  const foreign=await post('/api/native/command',{...command,requestId:randomUUID(),deviceId:randomUUID()});assert.equal(foreign.status,409);
  const norm=await post('/api/native/command',{requestId:randomUUID(),deviceId,serverId,module:'dailyNorm',action:'save',expectedUpdatedAt:null,input:{workRef:`case:${caseId}`,minutes:60,time:'09:30',days:[1,2,3,4,5,6,7],enabled:true}});assert.equal(norm.status,200);
  const daily=await (await fetch(origin+'/api/daily-norms')).json();assert.equal(daily.repeatMinutes,60);assert.equal(daily.norms[0].actualMinutes,null);
  const entries=await (await fetch(origin+'/api/time-entries')).json();assert.equal(entries.entries.length,0);
});
