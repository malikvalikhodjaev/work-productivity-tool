export function youtubeVideoUrl(value){
  if(typeof value!=='string'||value.length>3000)throw new Error('Укажи ссылку на видео YouTube.');
  let url;try{url=new URL(value.trim());}catch{throw new Error('Нужна полная ссылка YouTube или youtu.be.');}
  const host=url.hostname.toLowerCase();
  if(!['http:','https:'].includes(url.protocol)||url.username||url.password||url.port)throw new Error('Нужна обычная ссылка YouTube.');
  let id;
  if(host==='youtu.be')id=url.pathname.slice(1);
  else if(['youtube.com','www.youtube.com','m.youtube.com','music.youtube.com','www.youtube-nocookie.com'].includes(host))id=url.pathname==='/watch'?url.searchParams.get('v'):url.pathname.match(/^\/(?:embed|shorts|live)\/([^/]+)\/?$/)?.[1];
  if(!id||!/^[-_A-Za-z0-9]{11}$/.test(id))throw new Error('Не удалось найти видео. Вставь ссылку на конкретное видео YouTube.');
  return {id,watch:'https://www.youtube.com/watch?v='+id,embed:'https://www.youtube-nocookie.com/embed/'+id+'?playsinline=1&autoplay=0&loop=1&playlist='+id};
}

export function mountYoutube(host){
  const section=document.createElement('section');section.className='focus-youtube';section.dataset.localControl='true';
  section.innerHTML='<details><summary>YouTube · свой фон</summary><div class="focus-youtube-form"><label>Ссылка на YouTube<input id="focus-youtube-url" type="url" maxlength="3000" placeholder="Ссылка на видео"></label><button type="button" id="focus-youtube-open" class="button secondary">Открыть плеер</button><button type="button" id="focus-youtube-stop" class="text-button" disabled>Выключить видео</button></div><p id="focus-youtube-status" class="timer-note" role="status">Встроенные звуки работают без интернета. YouTube — при наличии сети.</p></details><div id="focus-youtube-player"></div><a id="focus-youtube-external" hidden target="_blank" rel="noopener">Открыть на YouTube ↗</a>';
  host.append(section);
  const field=section.querySelector('#focus-youtube-url'),player=section.querySelector('#focus-youtube-player'),status=section.querySelector('#focus-youtube-status'),stop=section.querySelector('#focus-youtube-stop'),external=section.querySelector('#focus-youtube-external');
  section.querySelector('#focus-youtube-open').addEventListener('click',()=>{
    try{const video=youtubeVideoUrl(field.value),frame=document.createElement('iframe');frame.title='YouTube · фон для работы';frame.src=video.embed;frame.allow='autoplay; encrypted-media; picture-in-picture; fullscreen';frame.allowFullscreen=true;frame.referrerPolicy='strict-origin-when-cross-origin';player.replaceChildren(frame);stop.disabled=false;external.href=video.watch;external.hidden=false;status.textContent='Нажми Play в плеере. Сворачивание таймера не закрывает плеер.';section.dataset.videoId=video.id;}
    catch(error){status.textContent=error.message;}
  });
  stop.addEventListener('click',()=>{player.replaceChildren();stop.disabled=true;external.hidden=true;delete section.dataset.videoId;status.textContent='Видео выключено';});
  window.addEventListener('pagehide',()=>player.replaceChildren());
}
