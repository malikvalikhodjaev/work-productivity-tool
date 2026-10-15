import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {timerRingtones,ringtonePreferences} from '../public/timer-ringtones.js';

test('Ringtone preferences reject unknown paths, corrupt values and out-of-range volume',()=>{
  assert.deepEqual(ringtonePreferences({id:'../../secret',volume:NaN}),{id:'bip_bip',volume:.65});
  assert.deepEqual(ringtonePreferences({id:'glass',volume:2}),{id:'glass',volume:1});
  assert.deepEqual(ringtonePreferences({id:'sonar',volume:-1}),{id:'sonar',volume:0});
  assert.equal(ringtonePreferences({volume:'1'}).volume,.65);
});
test('Every selectable sound is a real PCM file with headroom and matching web/native bytes',()=>{
  const hashes=new Set();
  for(const ringtone of timerRingtones){
    const buffer=fs.readFileSync(new URL(`../public/ringtones/${ringtone.id}.wav`,import.meta.url));
    assert.equal(buffer.toString('ascii',0,4),'RIFF');assert.equal(buffer.toString('ascii',8,12),'WAVE');
    assert.equal(buffer.readUInt16LE(20),1);assert.equal(buffer.readUInt16LE(34),16);
    const channels=buffer.readUInt16LE(22),rate=buffer.readUInt32LE(24),seconds=(buffer.length-44)/(rate*channels*2);
    assert.ok(seconds>=.4&&seconds<=3);
    let peak=0,energy=0;for(let i=44;i<buffer.length;i+=2){const sample=buffer.readInt16LE(i)/32768;peak=Math.max(peak,Math.abs(sample));energy+=sample*sample;}
    assert.ok(peak<.8&&peak>.1);assert.ok(energy>1);assert.equal(buffer.readInt16LE(44),0);
    const native=fs.readFileSync(new URL(ringtone.id==='classic'?'../native-app/assets/audio/alarm.wav':`../native-app/assets/audio/ringtones/${ringtone.id}.wav`,import.meta.url));
    assert.deepEqual(buffer,native);hashes.add(buffer.toString('base64'));
  }
  assert.equal(hashes.size,timerRingtones.length);
});
