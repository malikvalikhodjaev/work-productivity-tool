import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { createRemoteViewer, readRemoteConfig } from '../lib/remote-view.mjs';

test('Закрытый сервер требует аккаунт владельца, блокирует запись и не открывает произвольные файлы', async t => {
  let mutations = 0;
  const owner = http.createServer((req, res) => {
    if (req.method === 'POST') mutations++;
    res.setHeader('Content-Type', req.url === '/' ? 'text/html' : 'application/json');
    res.end(req.url === '/' ? '<html><head></head><body>Dashboard</body></html>' : JSON.stringify({ privateValue: 'личный результат' }));
  });
  owner.listen(0, '127.0.0.1'); await once(owner, 'listening');
  t.after(() => owner.close());
  const configFile = path.join(mkdtempSync(path.join(tmpdir(), 'dashboard-remote-')), 'remote-access.json');
  const gateway = createRemoteViewer({ configFile, ownerPort: owner.address().port, viewerPort: 0, assetPaths: new Set(['/']) });
  gateway.start(); await once(gateway.server, 'listening'); t.after(() => gateway.server.close());
  const request = (route, { login = 'owner@example.com', host = 'laptop.private-net.ts.net', method = 'GET', origin } = {}) => new Promise((resolve, reject) => {
    const req = http.request({ hostname: '127.0.0.1', port: gateway.server.address().port, path: route, method,
      headers: { host, ...(login ? { 'Tailscale-User-Login': login } : {}), ...(origin ? { origin } : {}) } }, res => {
      let body = ''; res.setEncoding('utf8'); res.on('data', part => { body += part; }); res.on('end', () => resolve({ code: res.statusCode, body, headers: res.headers }));
    }); req.on('error', reject); req.end();
  });
  assert.equal((await request('/api/dashboard')).code, 503, 'No configuration must not open private data.');
  writeFileSync(configFile, JSON.stringify({ version: 1, url: 'https://laptop.private-net.ts.net', allowedLogin: 'owner@example.com' }));
  for (const options of [{ login: '' }, { login: 'other@example.com' }, { host: 'attacker.example.com' }, { origin: 'https://attacker.example.com' }]) {
    const response = await request('/api/dashboard', options); assert.equal(response.code, 403); assert.ok(!response.body.includes('личный результат'));
  }
  const response = await request('/api/dashboard'); assert.equal(response.code, 200); assert.ok(response.body.includes('личный результат')); assert.equal(response.headers['cache-control'], 'no-store');
  assert.match((await request('/')).body, /name="dashboard-access" content="viewer"/);
  for (const method of ['POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']) assert.equal((await request('/api/portfolio', { method })).code, 403);
  for (const route of ['/data/dashboard.json', '/api/admin', '/api/entries', '/../data/remote-access.json', '//attacker.example.com/api/dashboard']) assert.equal((await request(route)).code, 404);
  assert.equal(mutations, 0, 'Blocked writes must not reach the owner server.');
  assert.equal(JSON.parse((await request('/api/mobile-access')).body).mode, 'viewer');
  writeFileSync(configFile, '{broken'); assert.equal((await request('/api/dashboard')).code, 503);
  assert.equal(gateway.status().configured, false);
});

test('Некорректные HTTPS-адреса и пустой аккаунт не включают доступ', () => {
  const file = path.join(mkdtempSync(path.join(tmpdir(), 'dashboard-remote-config-')), 'remote-access.json');
  for (const url of ['http://laptop.private-net.ts.net', 'https://public.example.com', 'https://laptop.private-net.ts.net:8443', 'https://laptop.private-net.ts.net/private', 'https://name:secret@laptop.private-net.ts.net', 'https://laptop.private-net.ts.net/?x=1']) {
    writeFileSync(file, JSON.stringify({ version: 1, url, allowedLogin: 'owner@example.com' })); assert.throws(() => readRemoteConfig(file));
  }
  writeFileSync(file, JSON.stringify({ version: 1, url: 'https://laptop.private-net.ts.net', allowedLogin: '' })); assert.throws(() => readRemoteConfig(file));
});
test('Рабочий шлюз допускает запись только владельцу с правильным Origin и перечисленным маршрутом',async t=>{
  const writes=[];
  const owner=http.createServer(async(req,res)=>{let body='';for await(const p of req)body+=p;writes.push({method:req.method,path:req.url,body,origin:req.headers.origin,host:req.headers.host});res.setHeader('Content-Type','application/json');res.end('{"saved":true}');});
  owner.listen(0,'127.0.0.1'); await once(owner,'listening');t.after(()=>owner.close());
  const configFile=path.join(mkdtempSync(path.join(tmpdir(),'iw-editor-')),'remote-access.json');
  writeFileSync(configFile,JSON.stringify({version:1,url:'https://laptop.private-net.ts.net',allowedLogin:'owner@example.com',access:'read-write'}));
  const gateway=createRemoteViewer({configFile,ownerPort:owner.address().port,viewerPort:0,assetPaths:new Set(['/'])});gateway.start();await once(gateway.server,'listening');t.after(()=>gateway.server.close());
  const send=(route,overrides={})=>new Promise((resolve,reject)=>{
    const headers=Object.fromEntries(Object.entries({host:'laptop.private-net.ts.net','Tailscale-User-Login':'owner@example.com',Origin:'https://laptop.private-net.ts.net','Content-Type':'application/json',...overrides.headers}).filter(([,v])=>v!==null));
    const req=http.request({hostname:'127.0.0.1',port:gateway.server.address().port,path:route,method:overrides.method??'POST',headers},res=>{res.resume();res.on('end',()=>resolve({status:res.statusCode}));});
    req.on('error',reject);req.end(overrides.body??'{"action":"pause"}');
  });
  assert.equal((await send('/api/timer',{headers:{Origin:''}})).status,403);
  assert.equal((await send('/api/timer',{headers:{'Tailscale-User-Login':'other@example.com'}})).status,403);
  assert.equal((await send('/api/timer',{headers:{Origin:'https://attacker.example'}})).status,403);
  assert.equal((await send('/api/offline/import',{headers:{Origin:'https://attacker.example'}})).status,403);
  assert.equal((await send('/api/admin')).status,404);
  assert.equal((await send('/api/timer',{headers:{'Content-Type':'text/plain'}})).status,415);
  assert.equal(writes.length,0);
  assert.equal((await send('/api/timer')).status,200); assert.equal(writes[0].path,'/api/timer');assert.equal(writes[0].origin,undefined);
  assert.equal(writes[0].host,`127.0.0.1:${owner.address().port}`);
  assert.equal((await send('/api/entries/00000000-0000-4000-8000-000000000001',{method:'DELETE',body:'',headers:{'Content-Type':null}})).status,200);
  assert.equal(writes.length,2);
  assert.equal((await send('/api/offline/connect')).status,200);
  assert.equal((await send('/api/offline/import')).status,200);
  assert.equal(writes.length,4);
});

test('Офлайн-режим не перехватывает и не сохраняет личные API-ответы', async () => {
  const listeners = new Map(); const cached = []; const fallbacks = [];
  const context = vm.createContext({ URL, Promise, self: { location: { origin: 'https://laptop.private-net.ts.net' }, addEventListener: (name, handler) => listeners.set(name, handler), skipWaiting: async () => {}, clients: { claim: async () => {} } },
    caches: { open: async () => ({ addAll: async urls => cached.push(...urls) }), match: async route => { fallbacks.push(route); return 'offline page'; } }, fetch: async () => { throw new Error('offline'); } });
  vm.runInContext(readFileSync(new URL('../public/service-worker.js', import.meta.url), 'utf8'), context);
  let installation; listeners.get('install')({ waitUntil: value => { installation = value; } }); await installation;
  assert.ok(cached.includes('/offline.html')); assert.ok(cached.every(route => !route.startsWith('/api/')));
  let intercepted = false;
  for (const route of ['/api/dashboard', '/api/finance', '/api/imported-data', '/api/references']) {
    listeners.get('fetch')({ request: { url: `https://laptop.private-net.ts.net${route}`, method: 'GET', mode: 'cors' }, respondWith: () => { intercepted = true; } });
  }
  assert.equal(intercepted, false);
  let navigation; listeners.get('fetch')({ request: { url: 'https://laptop.private-net.ts.net/', method: 'GET', mode: 'navigate' }, respondWith: value => { navigation = value; } });
  assert.equal(await navigation, 'offline page'); assert.deepEqual(fallbacks, ['/offline.html']);
});
