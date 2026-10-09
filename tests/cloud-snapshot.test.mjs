import test from 'node:test';
import assert from 'node:assert/strict';
import { createSnapshotView, validateSnapshot, memoryStorage } from '../lib/cloud-snapshot.mjs';

function sample(title = 'Тестовый проект') {
  return { format: 'indicators-work-snapshot', version: 1, capturedAt: '2026-10-09T08:00:00Z', attachments: [], files: {
    'dashboard.json': JSON.stringify({version:1,plans:{},entries:[],updatedAt:'2026-10-08T08:00:00Z',portfolio:{version:1,projects:[],alphas:[],tasks:[],history:[]}}),
    'workspace.json': JSON.stringify({version:1,systems:[],cases:[],goals:[],links:[],measurements:[],reviews:[],transactions:[],imports:[]}),
    'indicators.json': JSON.stringify({version:1,observations:[]}),
    'daily-problems.json': JSON.stringify({version:1,entries:[]}),
    'daily-results.json': JSON.stringify({version:1,entries:[]}),
    'references.json': JSON.stringify({version:1,entries:[{id:'test',title,group:'Мысли',note:'',originalText:title,revisions:[]}]})
  }};
}
test('cloud reads preserve raw snapshot while legacy stores write only to request memory', () => {
  const snapshot=sample(); const raw=JSON.stringify(snapshot);
  validateSnapshot(snapshot);
  const view=createSnapshotView(snapshot);
  for(const path of ['/api/dashboard?week=2030-01-07','/api/today','/api/overview?period=30d','/api/workspace','/api/imported-data','/api/finance?period=7d']) assert.ok(view.get(new URL(path,'https://example.test')));
  assert.equal(JSON.stringify(snapshot),raw);
  assert.equal(view.get(new URL('/api/imported-data','https://example.test')).reference.available,false);
});
test('separate views never leak content and unknown endpoints are not exposed', () => {
  const first=createSnapshotView(sample('Первый')),second=createSnapshotView(sample('Второй'));
  const url=new URL('/api/references','https://example.test');
  assert.equal(first.get(url).entries[0].title,'Первый'); assert.equal(second.get(url).entries[0].title,'Второй');
  assert.equal(first.get(new URL('/api/private-file','https://example.test')),undefined);
});
test('snapshot rejects arbitrary files and invalid attachment paths', () => {
  const a=sample();a.files['../secrets.json']='{}';assert.throws(()=>validateSnapshot(a),/Недопустимый файл/);
  const b=sample();b.attachments=[{path:'reference-assets/../private.png',sha256:'a'.repeat(64),size:100}];assert.throws(()=>validateSnapshot(b),/Неверное вложение/);
});
test('in-memory atomic replacement supports cross-platform paths', () => {
  const fs=memoryStorage({'references.json':'raw'});
  fs.writeFileSync('/data/file.tmp','next');fs.replaceFile('/data/file.tmp','/data/file.csv');
  assert.equal(fs.readFileSync('\\data\\file.csv','utf8'),'next');
  assert.equal(fs.existsSync('/data/file.tmp'),false); assert.equal(fs.readFileSync('/data/references.json','utf8'),'raw');
});
