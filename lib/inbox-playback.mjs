import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir,readFile,stat,rename,rm} from 'node:fs/promises';
import path from 'node:path';
import {randomUUID} from 'node:crypto';

const execute = promisify(execFile);
const maxBytes = 25 * 1024 * 1024;
const failure = (message,status=503) => Object.assign(new Error(message),{status});

export function createInboxPlayback({run=execute,binary=process.env.FFMPEG_BINARY??'ffmpeg'}={}) {
  const pending=new Map();
  return async function playback(original) {
    const name=path.basename(original.path);
    if(!/^[a-f0-9]{64}\.(ogg|mp3|m4a|wav)$/.test(name))throw failure('Неизвестный оригинал голосовой.',400);
    const folder=path.join(path.dirname(path.dirname(original.path)),'inbox-playback-cache');
    const target=path.join(folder,name.split('.')[0]+'-pcm16k-v1.wav');
    const info=async()=>({path:target,mime:'audio/wav',size:(await stat(target)).size});
    try {const cached=await info();if(cached.size>44&&cached.size<maxBytes)return cached;}catch{}
    if(pending.has(target))return pending.get(target);
    const operation=(async()=>{
      await mkdir(folder,{recursive:true});
      const temporary=path.join(folder,randomUUID()+'.wav');
      try {
        const format={ogg:'ogg',mp3:'mp3',m4a:'mov',wav:'wav'}[name.split('.').at(-1)];
        await run(binary,['-nostdin','-v','error','-protocol_whitelist','file,pipe','-f',format,'-i',original.path,
          '-map','0:a:0','-vn','-ac','1','-ar','16000','-c:a','pcm_s16le','-fs',String(maxBytes),'-y',temporary],
          {timeout:30000,maxBuffer:65536,windowsHide:true});
        const size=(await stat(temporary)).size;
        if(size>=maxBytes)throw failure('Голосовая слишком длинная для совместимого воспроизведения Windows. Оригинал сохранён.',413);
        const header=(await readFile(temporary)).subarray(0,12);
        if(size<=44||header.toString('ascii',0,4)!=='RIFF'||header.toString('ascii',8,12)!=='WAVE')throw failure('Не удалось подготовить совместимую копию голосовой.');
        await rename(temporary,target);
        return info();
      } catch(error) {
        if(error.status)throw error;
        throw failure('Не удалось подготовить голосовую для Windows. Оригинал сохранён; повтори позже.');
      } finally {await rm(temporary,{force:true});}
    })();
    pending.set(target,operation);
    try{return await operation;}finally{pending.delete(target);}
  };
}
