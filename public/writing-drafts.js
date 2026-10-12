export function createWritingDraftStore(factory=globalThis.indexedDB,name='indicators-work-writing-drafts-v1') {
  let opened;
  const open=()=>opened??=new Promise((resolve,reject)=>{
    const r=factory.open(name,1);r.onupgradeneeded=()=>r.result.createObjectStore('drafts',{keyPath:'key'});
    r.onsuccess=()=>{r.result.onversionchange=()=>{r.result.close();opened=null;};resolve(r.result);};r.onerror=()=>reject(r.error);r.onblocked=()=>reject(new Error('Закрой другие вкладки для обновления черновиков.'));
  });
  async function run(mode,operation){const db=await open();return new Promise((resolve,reject)=>{const tx=db.transaction('drafts',mode),s=tx.objectStore('drafts');let result;const r=operation(s);r.onsuccess=()=>{result=r.result;};tx.oncomplete=()=>resolve(result);tx.onerror=tx.onabort=()=>reject(tx.error??new Error('Не удалось сохранить локальный черновик.'));});}
  async function removeIf(key,token){const db=await open();return new Promise((resolve,reject)=>{const tx=db.transaction('drafts','readwrite'),s=tx.objectStore('drafts'),r=s.get(key);r.onsuccess=()=>{if(r.result?.token===token)s.delete(key);};tx.oncomplete=()=>resolve();tx.onerror=tx.onabort=()=>reject(tx.error);});}
  return {put:draft=>run('readwrite',s=>s.put(structuredClone(draft))),remove:key=>run('readwrite',s=>s.delete(key)),removeIf,list:async()=>((await run('readonly',s=>s.getAll()))??[]).sort((a,b)=>b.savedAt.localeCompare(a.savedAt)),close:async()=>{(await open()).close();opened=null;}};
}
