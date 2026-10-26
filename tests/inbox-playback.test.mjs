import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createInboxPlayback} from '../lib/inbox-playback.mjs';

async function fixture(t) {
  const dir=await mkdtemp(path.join(tmpdir(),'iw-playback-'));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const file=path.join(dir,'inbox-audio','a'.repeat(64)+'.ogg');
  await mkdir(path.dirname(file));await writeFile(file,'OggS original');
  return {path:file,mime:'audio/ogg'};
}
function wav() {const bytes=Buffer.alloc(46);bytes.write('RIFF');bytes.write('WAVE',8);return bytes;}
test('compatible audio caches a derived WAV, deduplicates concurrent conversion and leaves original intact',async t=>{
  const original=await fixture(t);let calls=0;
  const playback=createInboxPlayback({run:async(binary,args,options)=>{
    calls++;assert.equal(binary,'ffmpeg');assert.equal(args[args.indexOf('-f')+1],'ogg');
    assert.equal(args[args.indexOf('-protocol_whitelist')+1],'file,pipe');assert.equal(options.timeout,30000);
    await writeFile(args.at(-1),wav());
  }});
  const [a,b]=await Promise.all([playback(original),playback(original)]);
  assert.equal(a.path,b.path);assert.equal(a.mime,'audio/wav');assert.equal(calls,1);
  await playback(original);assert.equal(calls,1);
  assert.equal(await readFile(original.path,'utf8'),'OggS original');
});
test('failed conversion is retryable and never replaces original',async t=>{
  const original=await fixture(t);let fail=true;
  const playback=createInboxPlayback({run:async(binary,args)=>{await writeFile(args.at(-1),wav());if(fail)throw Error('decoder failed');}});
  await assert.rejects(playback(original),e=>e.status===503);
  assert.equal(await readFile(original.path,'utf8'),'OggS original');
  fail=false;assert.equal((await playback(original)).mime,'audio/wav');
});
test('rejects untrusted source paths before running a decoder',async()=>{
  const playback=createInboxPlayback({run:async()=>{assert.fail('must not run');}});
  await assert.rejects(playback({path:'/tmp/message.m3u'}),e=>e.status===400);
});
