import { env } from 'cloudflare:workers';
import indexHtml from './shells/index.html?raw';
import alphasHtml from './shells/alphas.html?raw';
import timeSources from './docs/ADR-001-time-sources.md?raw';
import workLoop from './docs/ADR-002-personal-work-loop.md?raw';
import { createSnapshotView, validateSnapshot } from './lib/cloud-snapshot.mjs';

const headers = {
  'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'same-origin',
  'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-src 'self'; frame-ancestors 'self'; base-uri 'none'; form-action 'self'"
};
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { ...headers, 'Content-Type': 'application/json; charset=utf-8' } });
const text = (value: string, contentType: string) => new Response(value, { headers: { ...headers, 'Content-Type': contentType } });
const digest = async (bytes: Uint8Array) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))).map(value => value.toString(16).padStart(2,'0')).join('');
const key = (sha: string, path: string) => `snapshots/${sha}/${path}`;

async function current() {
  if (!env.DB) throw new Error('Snapshot database unavailable.');
  return env.DB.prepare('SELECT v.sha, v.payload, v.captured_at FROM snapshot_versions v JOIN snapshot_head h ON v.sha=h.sha WHERE h.id=?').bind('active').first<{sha:string,payload:string,captured_at:string}>();
}

// All routes use the confirmed owner-private Sites policy, including service
// access validated/consumed by dispatch. Never make this Site public with this
// shared updater enabled. Raw datasets arrive here only after deployment.
async function importSnapshot(request: Request) {
  const origin = request.headers.get('origin');
  if (origin && origin !== new URL(request.url).origin) return json({error:'Запрос с другого сайта запрещён.'},403);
  if (!request.headers.get('content-type')?.startsWith('application/json')) return json({error:'Нужен JSON.'},415);
  const length=Number(request.headers.get('content-length')||0);
  if(length>4500000) return json({error:'Слишком большой снимок.'},413);
  const parts:Uint8Array[]=[];let bytes=0;
  const reader=request.body?.getReader();if(!reader)return json({error:'Нет снимка.'},400);
  while(true){const item=await reader.read();if(item.done)break;bytes+=item.value.length;if(bytes>4500000){await reader.cancel();return json({error:'Слишком большой снимок.'},413);}parts.push(item.value);}
  const buffer=new Uint8Array(bytes);let offset=0;for(const part of parts){buffer.set(part,offset);offset+=part.length;}
  const input=JSON.parse(new TextDecoder().decode(buffer));
  const snapshot=validateSnapshot(input.snapshot);
  const previous=await current();
  if((previous?.sha??null)!==input.expectedSha)return json({error:'Снимок уже обновлён. Перечитай текущую версию.'},409);
  if(!env.BUCKET||!env.DB)throw new Error('Storage unavailable.');
  const payload=JSON.stringify(snapshot),sha=await digest(new TextEncoder().encode(payload));
  const attachments=input.attachmentBytes;
  if(!attachments||typeof attachments!=='object'||Array.isArray(attachments)||Object.keys(attachments).length!==snapshot.attachments.length)throw new Error('Неверные данные вложений.');
  // Validate every attachment before writing any of the replacement snapshot.
  const decoded=[];
  for(const item of snapshot.attachments){
    const base64=attachments[item.path];if(typeof base64!=='string'||base64.length>7000000)throw new Error('Неверное вложение.');
    const value=Uint8Array.from(atob(base64),char=>char.charCodeAt(0));
    if(value.length!==item.size||await digest(value)!==item.sha256||value.slice(0,8).join(',')!=='137,80,78,71,13,10,26,10')throw new Error('Вложение не соответствует снимку.');
    decoded.push({item,value});
  }
  for(const {item,value} of decoded)await env.BUCKET.put(key(sha,item.path),value,{httpMetadata:{contentType:'image/png'}});
  const insert=env.DB.prepare('INSERT OR IGNORE INTO snapshot_versions (sha,payload,captured_at,imported_at) VALUES (?,?,?,?)').bind(sha,payload,snapshot.capturedAt,new Date().toISOString());
  const activate=previous
    ?env.DB.prepare('UPDATE snapshot_head SET sha=? WHERE id=? AND sha=?').bind(sha,'active',previous.sha)
    :env.DB.prepare('INSERT OR IGNORE INTO snapshot_head (id,sha) VALUES (?,?)').bind('active',sha);
  const result=await env.DB.batch([insert,activate]);
  if(result[1].meta.changes!==1)return json({error:'Другая загрузка уже обновила снимок.'},409);
  return json({ok:true,sha,capturedAt:snapshot.capturedAt,files:Object.keys(snapshot.files).length,attachments:snapshot.attachments.length});
}

export async function handle(request: Request) {
  const url=new URL(request.url);
  try{
    if(request.method==='POST'&&url.pathname==='/api/cloud/snapshot')return await importSnapshot(request);
    if(!['GET','HEAD'].includes(request.method))return json({error:'Веб-версия предназначена для просмотра. Редактирование — на ПК.'},403);
    if(url.pathname==='/'||url.pathname==='/alphas')return text(url.pathname==='/'?indexHtml:alphasHtml,'text/html; charset=utf-8');
    if(url.pathname==='/adr/time-sources')return text(timeSources,'text/plain; charset=utf-8');
    if(url.pathname==='/adr/work-loop')return text(workLoop,'text/plain; charset=utf-8');
    // Unknown browser pages return to the dashboard. Authentication and its
    // reserved routes remain dispatch-owned; no auth code is read or replayed.
    if(!url.pathname.startsWith('/api/')&&request.headers.get('accept')?.includes('text/html'))return new Response(null,{status:303,headers:{...headers,Location:url.origin+'/'}});
    const record=await current();
    if(url.pathname==='/api/health')return json({ok:true,service:'indicators-work-dashboard',version:'1.3.0',timezone:'Asia/Tashkent',snapshotReady:Boolean(record),capturedAt:record?.captured_at??null});
    if(url.pathname==='/api/mobile-access')return json({mode:'viewer',provider:'sites',configured:true,gatewayReady:true,url:url.origin,access:'read-only',requiresComputer:false,capturedAt:record?.captured_at??null,sha:record?.sha??null});
    if(!record)return json({error:'No Data · снимок ещё не загружен.'},503);
    const snapshot=JSON.parse(record.payload),view=createSnapshotView(snapshot);
    if(/^\/api\/references\/[a-z0-9-]+\/attachment$/.test(url.pathname)){
      const file=view.attachment(url.pathname.split('/')[3]);
      if(!file||!env.BUCKET)return json({error:'No Data · вложение не найдено.'},404);
      const object=await env.BUCKET.get(key(record.sha,file.path));
      return object?new Response(object.body,{headers:{...headers,'Content-Type':'image/png'}}):json({error:'No Data · вложение не найдено.'},404);
    }
    const value=view.get(url);
    return value===undefined?json({error:'Страница не найдена.'},404):json(value);
  }catch(error){
    const message=error instanceof Error?error.message:'Не удалось загрузить снимок.';
    const internal=/database|SQLITE|D1_|unavailable|ENOENT/i.test(message);
    if(internal)console.error('Snapshot service unavailable.');
    return json({error:internal?'Не удалось прочитать данные. Повтори попытку.':message},internal?500:400);
  }
}
