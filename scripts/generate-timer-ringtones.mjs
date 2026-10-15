import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {timerRingtones} from '../public/timer-ringtones.js';
const root=path.dirname(path.dirname(fileURLToPath(import.meta.url))),rate=22050;
const specifications={
  bip_bip:{seconds:1.7,notes:[[0,740,.15],[.24,740,.15],[.85,740,.15],[1.09,740,.15]],kind:'beep'},
  sonar:{seconds:2.4,notes:[[0,440,.55],[.7,554.37,.55],[1.4,440,.75]],kind:'sonar'},
  glass:{seconds:2.3,notes:[[0,1046.5,1.15],[.32,1318.51,1.15],[.64,1567.98,1.5]],kind:'glass'},
  marimba:{seconds:2.1,notes:[[0,523.25,.65],[.26,659.25,.65],[.52,783.99,.65],[.88,1046.5,1.05]],kind:'wood'},
  orbit:{seconds:2.6,notes:[[0,392,.7],[.3,587.33,.7],[.95,783.99,.85],[1.5,523.25,.9]],kind:'sonar'},
  warm_bell:{seconds:2.9,notes:[[0,440,1.65],[1.05,523.25,1.65]],kind:'bell'}
};
function wav(spec){
  const count=Math.ceil(spec.seconds*rate),samples=new Float64Array(count);
  for(const [start,freq,length] of spec.notes)for(let i=Math.ceil(start*rate);i<Math.min(count,Math.ceil((start+length)*rate));i++){
    const t=i/rate-start,progress=t/length;
    const attack=Math.min(1,t/.012),release=Math.min(1,(length-t)/.07);
    const envelope=attack*release*(spec.kind==='beep'?Math.pow(Math.sin(Math.PI*progress),.35):Math.exp(-progress*(spec.kind==='wood'?6:3.6)));
    const partials=spec.kind==='glass'?[[1,1],[2.76,.25],[4.07,.08]]:spec.kind==='wood'?[[1,1],[3.96,.2],[9,.025]]:spec.kind==='bell'?[[1,1],[2.01,.32],[3.98,.1]]:[[1,1],[2,.1]];
    samples[i]+=partials.reduce((sum,[multiple,gain])=>sum+gain*Math.sin(2*Math.PI*freq*multiple*t),0)*envelope;
  }
  const peak=samples.reduce((v,s)=>Math.max(v,Math.abs(s)),0),scale=.66/peak;
  const data=Buffer.alloc(count*2);for(let i=0;i<count;i++)data.writeInt16LE(Math.round(samples[i]*scale*32767),i*2);
  const out=Buffer.alloc(44+data.length);out.write('RIFF');out.writeUInt32LE(out.length-8,4);out.write('WAVEfmt ',8);out.writeUInt32LE(16,16);out.writeUInt16LE(1,20);out.writeUInt16LE(1,22);out.writeUInt32LE(rate,24);out.writeUInt32LE(rate*2,28);out.writeUInt16LE(2,32);out.writeUInt16LE(16,34);out.write('data',36);out.writeUInt32LE(data.length,40);data.copy(out,44);return out;
}
for(const directory of ['public/ringtones','native-app/assets/audio/ringtones']){
  const target=path.join(root,directory);fs.mkdirSync(target,{recursive:true});
  for(const [id,spec] of Object.entries(specifications))fs.writeFileSync(path.join(target,`${id}.wav`),wav(spec));
}
fs.copyFileSync(path.join(root,'native-app/assets/audio/alarm.wav'),path.join(root,'public/ringtones/classic.wav'));
fs.writeFileSync(path.join(root,'public/ringtones/catalog.json'),JSON.stringify({version:1,default:'bip_bip',ringtones:timerRingtones},null,2)+'\n');
console.log('Generated six original PCM ringtones and retained the classic signal.');
