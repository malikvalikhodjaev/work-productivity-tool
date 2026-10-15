import * as fs from 'node:fs';
import path from 'node:path';
import {randomBytes,timingSafeEqual} from 'node:crypto';
import {replaceFile} from './atomic-file.mjs';
import {INBOX_AUDIO_LIMIT} from './inbox.mjs';

const tokenPattern=/^\d{5,16}:[A-Za-z0-9_-]{25,100}$/;
const safeEqual=(a,b)=>typeof a==='string'&&typeof b==='string'&&Buffer.byteLength(a)===Buffer.byteLength(b)&&timingSafeEqual(Buffer.from(a),Buffer.from(b));
export function createTelegramBot({file,inbox,fetcher=fetch,now=()=>Date.now(),autoStart=true}) {
  let config=fs.existsSync(file)?JSON.parse(fs.readFileSync(file,'utf8')):null;
  let controller=null,timer=null,generation=0,running=false,lastPoll=null,lastError=null;
  const persist=next=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file+'.tmp',JSON.stringify(next,null,2)+'\n',{mode:0o600});replaceFile(file+'.tmp',file);config=next;};
  function status(){return {configured:!!config?.token,enabled:config?.enabled??false,paired:!!config?.ownerId,username:config?.username??null,botUrl:config?.username?`https://t.me/${config.username}`:null,pairingUrl:config?.pairCode&&config.pairExpires>now()?`https://t.me/${config.username}?start=${config.pairCode}`:null,pairExpires:config?.pairExpires??null,lastPoll,lastError,running};}
  async function call(token,method,body={},signal) {
    let response;
    try{response=await fetcher(`https://api.telegram.org/bot${token}/${method}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),signal:signal??AbortSignal.timeout(15000)});}catch(e){if(e.name==='AbortError')throw e;throw new Error('Нет соединения с Telegram. Повторим подключение.');}
    let value;try{value=await response.json();}catch{throw new Error('Telegram вернул неполный ответ.');}
    if(!response.ok||!value.ok)throw new Error(value.error_code===401?'Telegram не принял токен бота.':value.error_code===409?'Бот уже используется другим сервером или webhook. Останови другое подключение.':'Telegram временно отклонил запрос.');
    return value.result;
  }
  function stop(){generation++;controller?.abort();controller=null;clearTimeout(timer);timer=null;running=false;}
  function schedule(delay=0){clearTimeout(timer);if(autoStart&&config?.enabled) {timer=setTimeout(()=>void poll(),delay);timer.unref?.();}}
  function start(){stop();if(config?.enabled)schedule();}
  async function configure(input) {
    if(typeof input.token!=='string'||!tokenPattern.test(input.token.trim()))throw new Error('Вставь токен Telegram-бота из BotFather.');
    const token=input.token.trim(),bot=await call(token,'getMe'),webhook=await call(token,'getWebhookInfo');
    if(webhook.url)throw new Error('У этого бота уже настроен webhook. Подключи отдельного бота для заметок.');
    if(!/^\w{5,64}$/.test(bot.username??'')||!Number.isSafeInteger(bot.id))throw new Error('Не удалось проверить Telegram-бота.');
    stop();const same=config?.botId===String(bot.id);
    persist({version:1,token,botId:String(bot.id),username:bot.username,enabled:true,ownerId:same?config.ownerId??null:null,pairCode:same&&config.ownerId?null:randomBytes(24).toString('base64url'),pairExpires:now()+15*60*1000});
    lastError=null;start();return status();
  }
  function control(action) {
    if(!config?.token)throw new Error('Сначала подключи Telegram-бота.');
    if(action==='pause'){stop();persist({...config,enabled:false});}
    else if(action==='resume'){persist({...config,enabled:true});start();}
    else if(action==='pair'){if(config.ownerId)throw new Error('Бот уже привязан к твоему Telegram-аккаунту.');persist({...config,pairCode:randomBytes(24).toString('base64url'),pairExpires:now()+15*60*1000});}
    else throw new Error('Неизвестное действие бота.');
    return status();
  }
  async function handle(update, captured) {
    if(!Number.isSafeInteger(update.update_id)||update.update_id<0)throw new Error('Telegram вернул неверный идентификатор сообщения.');
    if(update.update_id<inbox.cursor(captured.botId))return;
    const message=update.message??update.edited_message;
    const privateSender=message?.chat?.type==='private'&&!message.from?.is_bot&&Number.isSafeInteger(message.from?.id)&&message.chat.id===message.from.id;
    if(!privateSender){inbox.skip(captured.botId,update.update_id);return;}
    const sender=String(message.from.id);
    if(!config.ownerId) {
      const code=message.text?.match(/^\/start(?:@\w+)?\s+([A-Za-z0-9_-]+)\s*$/)?.[1];
      if(config.pairExpires>now()&&safeEqual(code,config.pairCode)){
        persist({...config,ownerId:sender,pairCode:null,pairExpires:null});
        await call(captured.token,'sendMessage',{chat_id:message.chat.id,text:'Твой Telegram подключён к Indicators & Work. Присылай сюда текст и голосовые — они появятся в «Письмо → Входящие мысли».'}).catch(()=>{});
      }
      inbox.skip(captured.botId,update.update_id);return;
    }
    if(sender!==config.ownerId){inbox.skip(captured.botId,update.update_id);return;}
    if(/^\/(start|help)(?:@\w+)?(?:\s|$)/.test(message.text??'')){inbox.skip(captured.botId,update.update_id);return;}
    const item=inbox.receive(captured.botId,update);
    if(item && update.message)await call(captured.token,'sendMessage',{chat_id:message.chat.id,text:'Сохранено во «Входящих мыслях».',reply_parameters:{message_id:message.message_id,allow_sending_without_reply:true}}).catch(()=>{});
  }
  async function download(captured,item,signal) {
    const meta=await call(captured.token,'getFile',{file_id:item.fileId},signal);
    if(meta.file_size>INBOX_AUDIO_LIMIT){inbox.audioError(item.id,'Файл больше 20 MB.',true);return;}
    if(typeof meta.file_path!=='string'||! /^[A-Za-z0-9_./-]+$/.test(meta.file_path)||meta.file_path.split('/').includes('..')||meta.file_path.startsWith('/'))throw new Error('Не удалось получить файл голосовой записи.');
    let response;try{response=await fetcher(`https://api.telegram.org/file/bot${captured.token}/${meta.file_path}`,{signal,redirect:'error'});}catch{throw new Error('Аудио пока не загружено. Повторим загрузку.');}
    if(!response.ok||!response.body)throw new Error('Аудио пока недоступно. Повторим загрузку.');
    const parts=[];let bytes=0;
    for await(const part of response.body){bytes+=part.length;if(bytes>INBOX_AUDIO_LIMIT){inbox.audioError(item.id,'Файл больше 20 MB.',true);return;}parts.push(Buffer.from(part));}
    inbox.saveAudio(item.id,Buffer.concat(parts));
  }
  async function poll() {
    if(!config?.enabled||running)return;
    running=true;const captured={...config},epoch=generation;
    controller=new AbortController();const requestController=controller;
    const deadline=setTimeout(()=>requestController.abort(),40000);deadline.unref?.();
    try {
      const updates=await call(captured.token,'getUpdates',{offset:inbox.cursor(captured.botId),timeout:25,limit:50,allowed_updates:['message','edited_message']},requestController.signal);
      if(epoch!==generation)return;
      for(const update of updates){if(epoch!==generation)return;await handle(update,captured);}
      lastPoll=new Date(now()).toISOString();lastError=null;
      for(const item of inbox.pendingAudio(captured.botId).slice(0,5)) {
        if(epoch!==generation)return;
        try{await download(captured,item,requestController.signal);}catch(e){if(epoch===generation)inbox.audioError(item.id,'Аудио пока не загружено. Повторим загрузку.');}
      }
    }catch(e){if(epoch===generation)lastError=e.name==='AbortError'?'Telegram пока не ответил. Повторим запрос.':e.message;}
    finally{clearTimeout(deadline);if(epoch===generation){controller=null;running=false;schedule(lastError?5000:300);}}
  }
  return {status,configure,control,start,stop,poll};
}
