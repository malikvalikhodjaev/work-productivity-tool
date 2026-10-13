import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const root=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const assets=path.join(root,'native-app','assets');
fs.mkdirSync(path.join(assets,'audio'),{recursive:true});
const png=fs.readFileSync(path.join(root,'public','icon-192.png'));
fs.writeFileSync(path.join(assets,'iw.png'),png);
const ico=Buffer.alloc(22+png.length);ico.writeUInt16LE(1,2);ico.writeUInt16LE(1,4);ico[6]=192;ico[7]=192;ico.writeUInt16LE(1,10);ico.writeUInt16LE(32,12);ico.writeUInt32LE(png.length,14);ico.writeUInt32LE(22,18);png.copy(ico,22);fs.writeFileSync(path.join(assets,'iw.ico'),ico);
const source=fs.readFileSync(path.join(root,'public','reflection-hints.js'),'utf8');
const start=source.indexOf('const blocks = [')+'const blocks = '.length,end=source.indexOf('\n];',start)+2;
if(start<15||end<start)throw new Error('Question library definition was not found.');
const blocks=vm.runInNewContext('('+source.slice(start,end)+')',Object.create(null),{timeout:1000});
fs.writeFileSync(path.join(assets,'reflection-hints.json'),JSON.stringify(blocks,null,2)+'\n');
for(const type of ['white','pink','brown','rain','wind','lofi','alarm']){
  const rate=22050,seconds=type==='alarm'?.5:type==='lofi'?12:8,length=Math.round(rate*seconds),data=Buffer.alloc(length*4);
  let seed=91431,brown=0,b0=0,b1=0,b2=0,b3=0,b4=0,b5=0,b6=0;
  for(let i=0;i<length;i++){
    seed=(Math.imul(seed,1664525)+1013904223)>>>0;const w=seed/2147483648-1,t=i/rate;let value;
    if(type==='white')value=w*.35;
    else if(type==='brown'||type==='wind'){brown=(brown+.02*w)/1.02;value=brown*3.5*(type==='wind'?.6+.3*Math.sin(t*1.3):1);}
    else if(type==='alarm')value=Math.sin(2*Math.PI*660*t)*.18;
    else if(type==='lofi'){const chords=[[48,55,59,64],[45,52,55,60],[41,48,52,57],[43,50,53,59]],notes=chords[Math.floor(t/3)%4],phase=t%3,envelope=Math.min(1,phase/.04)*Math.min(1,(3-phase)/.18);value=notes.reduce((sum,n)=>{const f=440*2**((n-69)/12);return sum+Math.sin(2*Math.PI*f*t)*.045+Math.sin(2*Math.PI*f*2*t)*.008;},0)*envelope;const beat=t%.75;value+=Math.sin(2*Math.PI*(45+65*Math.exp(-beat*45))*beat)*Math.exp(-beat*22)*.14+w*.009;}
    else{b0=.99886*b0+w*.0555179;b1=.99332*b1+w*.0750759;b2=.969*b2+w*.153852;b3=.8665*b3+w*.3104856;b4=.55*b4+w*.5329522;b5=-.7616*b5-w*.016898;value=(b0+b1+b2+b3+b4+b5+b6+w*.5362)*.11;b6=w*.115926;if(type==='rain')value=value*.55+w*(.18+.12*Math.sin(t*2.1));}
    const fade=Math.min(1,i/(rate*.02),(length-1-i)/(rate*.02)),sample=Math.round(Math.max(-.85,Math.min(.85,value))*fade*32767);
    data.writeInt16LE(sample,i*4);data.writeInt16LE(sample,i*4+2);
  }
  const wav=Buffer.alloc(44+data.length);wav.write('RIFF');wav.writeUInt32LE(wav.length-8,4);wav.write('WAVEfmt ',8);wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(2,22);wav.writeUInt32LE(rate,24);wav.writeUInt32LE(rate*4,28);wav.writeUInt16LE(4,32);wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(data.length,40);data.copy(wav,44);fs.writeFileSync(path.join(assets,'audio',type+'.wav'),wav);
}
process.stdout.write('Native icons, questions and seven local audio assets prepared.\n');
