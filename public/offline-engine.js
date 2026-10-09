export async function postOffline(path, body) {
  const response = await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),cache:'no-store',signal:AbortSignal.timeout(10000)});
  const result = await response.json();
  if (!response.ok) { const error=new Error(result.error||'Не удалось отправить запись.'); error.kind=result.kind; error.details=result.details; error.http=response.status; throw error; }
  return result;
}
export async function syncDevice(store, post = postOffline) {
  let state=await store.read();
  if(!state?.context) return state;
  const context=await post('/api/offline/connect',{deviceId:state.deviceId});
  if(context.serverId!==state.context.serverId) throw new Error('Адрес ведёт к другому серверу. Локальные записи не отправлены. Выгрузи их и вернись к прежнему серверу.');
  state=await store.update(s=>{s.context=context;});
  for(const r of Object.values(state.queue).filter(r=>r.status==='pending')) {
    try {
      const result=await post('/api/offline/import',{deviceId:state.deviceId,serverId:r.serverId,session:r.session,...(r.resolution?{resolution:r.resolution}:{})});
      state=await store.update(s=>{s.queue[r.session.id]={...s.queue[r.session.id],status:'synced',receipt:result.receipt,error:null,details:[]};});
    } catch(e) {
      if(!e.http||e.http>=500) throw e;
      state=await store.update(s=>{const current=s.queue[r.session.id]; if(current.status!=='synced') s.queue[r.session.id]={...current,status:'conflict',error:e.message,kind:e.kind??'offline_error',details:e.details??[]};});
    }
  }
  return state;
}
