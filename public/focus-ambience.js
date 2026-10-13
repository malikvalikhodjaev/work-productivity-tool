import {mountYoutube} from './focus-youtube.js';
const themes={green:'Зелень',evening:'Вечер',desert:'Пустыня',lofi:'Лофи'};
const sounds={white:'Белый шум',pink:'Розовый шум',brown:'Коричневый шум',rain:'Дождь',wind:'Ветер',lofi:'Лофи'};
const art=`<svg class="focus-art" viewBox="0 0 960 300" preserveAspectRatio="xMidYMid slice" aria-hidden="true"><g data-scene="green"><circle cx="755" cy="50" r="95" fill="#e5efb6" opacity=".32"/><path d="M0 208 Q210 97 410 213 T960 155V300H0Z" fill="#719b79"/><path d="M0 255 Q270 175 500 252 T960 210V300H0Z" fill="#315e48"/><g fill="#234b3b"><path d="M82 17l-52 151h32l-47 82h137l-49-82h30Z"/><path d="M877 44l-49 134h28l-43 83h137l-50-83h28Z"/><path d="M172 135l-35 92h22l-27 59h87l-26-59h19Z"/></g><path d="M286 300Q412 241 557 270T747 300" fill="none" stroke="#b7c89c" stroke-width="23" opacity=".35"/></g><g data-scene="evening"><circle cx="744" cy="88" r="61" fill="#ffc78e"/><path d="M0 213L150 154 310 237 490 132 680 242 847 187 960 220V300H0Z" fill="#51466a"/><path d="M0 268Q276 216 449 269T960 250V300H0Z" fill="#302b48"/><g fill="#ffdfc0"><circle cx="89" cy="46" r="2"/><circle cx="510" cy="48" r="2"/><circle cx="861" cy="36" r="2"/><circle cx="313" cy="90" r="1.5"/><circle cx="633" cy="25" r="1.5"/></g></g><g data-scene="desert"><circle cx="760" cy="70" r="54" fill="#fcdf9b"/><path d="M0 226Q220 98 480 234T960 159V300H0Z" fill="#cc9467"/><path d="M0 278Q220 194 496 263T960 225V300H0Z" fill="#e9bc87"/><path d="M637 300Q709 245 827 239" fill="none" stroke="#b98159" stroke-width="2"/><path d="M662 300Q739 258 861 253" fill="none" stroke="#b98159" stroke-width="2"/></g><g data-scene="lofi"><rect x="674" y="15" width="180" height="222" rx="8" fill="#242d50" stroke="#cba090" stroke-width="5"/><circle cx="811" cy="56" r="25" fill="#f5dbad"/><path d="M680 166h34v-32h25v51h32v-67h29v29h26v-23h23v108H680Z" fill="#131c37"/><path d="M764 17v218M676 118h176" stroke="#cba090" stroke-width="4"/><path d="M585 251h375v49H585Z" fill="#4d303e"/><path d="M594 244h344v10H594Z" fill="#bc897a"/><rect x="731" y="230" width="54" height="13" rx="3" fill="#dfb88f"/><path d="M899 236v-57" stroke="#607f74" stroke-width="4"/><path d="M899 203q-40-29-28-45 33 1 28 45M899 218q31-35 38-18-6 29-38 18" fill="#7f9d81"/><path d="M880 224h36l-5 21h-26Z" fill="#cc9d79"/><g fill="#dfad82" opacity=".6"><rect x="58" y="84" width="90" height="5"/><rect x="72" y="89" width="5" height="38"/><rect x="116" y="91" width="5" height="24"/></g></g></svg>`;

function bufferFor(context,type) {
  const rate=context.sampleRate,length=Math.round(rate*(type==='lofi'?12:8)),buffer=context.createBuffer(2,length,rate);
  for(let channel=0;channel<2;channel++){
    const data=buffer.getChannelData(channel);let brown=0,b0=0,b1=0,b2=0,b3=0,b4=0,b5=0,b6=0;
    for(let i=0;i<length;i++){
      const t=i/rate,w=Math.random()*2-1;let value;
      if(type==='white')value=w*.6;
      else if(type==='brown'||type==='wind'){brown=(brown+.02*w)/1.02;value=brown*3.5*(type==='wind'?.6+.3*Math.sin(t*1.3):1);}
      else if(type==='lofi'){
        const chords=[[48,55,59,64],[45,52,55,60],[41,48,52,57],[43,50,53,59]],notes=chords[Math.floor(t/3)%4];
        const phase=t%3,envelope=Math.min(1,phase/.04)*Math.min(1,(3-phase)/.18);
        value=notes.reduce((sum,n)=>{const f=440*Math.pow(2,(n-69)/12);return sum+Math.sin(2*Math.PI*f*t+channel*.15)*.045+Math.sin(2*Math.PI*f*2*t)*.008;},0)*envelope;
        const beat=t%.75;value+=Math.sin(2*Math.PI*(45+65*Math.exp(-beat*45))*beat)*Math.exp(-beat*22)*.14+w*.009;
        if(Math.floor(t/.75)%2)value+=w*Math.exp(-beat*70)*.028;
      } else {
        b0=.99886*b0+w*.0555179;b1=.99332*b1+w*.0750759;b2=.969*b2+w*.153852;b3=.8665*b3+w*.3104856;b4=.55*b4+w*.5329522;b5=-.7616*b5-w*.016898;
        value=(b0+b1+b2+b3+b4+b5+b6+w*.5362)*.11;b6=w*.115926;
        if(type==='rain')value=value*.55+w*(.18+.12*Math.sin(t*2.1));
      }
      const fade=Math.min(1,i/(rate*.02),(length-1-i)/(rate*.02));data[i]=Math.max(-.85,Math.min(.85,value))*fade;
    }
  }
  return buffer;
}

export function mountFocusAmbience(panel,{allowExpand=true}={}) {
  let saved={};try{saved=JSON.parse(localStorage.getItem('iw-focus-preferences')??'{}')??{};}catch{}
  let theme=Object.hasOwn(themes,saved.theme)?saved.theme:'green',sound=Object.hasOwn(sounds,saved.sound)?saved.sound:'rain',volume=Number.isFinite(saved.volume)?Math.max(0,Math.min(100,saved.volume)):25;
  const host=document.createElement('div');host.className='focus-ambience';host.dataset.localControl='true';
  host.innerHTML=`<div class="focus-themes" role="group" aria-label="Тема фокуса">${Object.entries(themes).map(([id,label])=>`<button type="button" data-focus-theme="${id}" aria-pressed="false">${label}</button>`).join('')}<button type="button" id="focus-expand" class="focus-expand" aria-pressed="false">Развернуть ↗</button></div><div class="focus-scene">${art}<div class="focus-scene-content"><p id="focus-scene-label">ПРОСТРАНСТВО ДЛЯ ВАЖНОГО</p><div id="focus-clock-host"></div><p id="focus-scene-work">Выбери карточку работы</p></div></div><div class="focus-sound-controls"><label>Звук<select id="focus-sound">${Object.entries(sounds).map(([id,label])=>`<option value="${id}">${label}</option>`).join('')}</select></label><button id="focus-sound-toggle" type="button" class="button secondary" aria-pressed="false">▶ Слушать</button><label class="focus-volume">Громкость<input id="focus-volume" type="range" min="0" max="100" step="1" aria-label="Громкость фонового звука"></label><span id="focus-sound-status" role="status">Звук выключен</span></div>`;
  (panel.querySelector('.timer-heading')??panel.querySelector('h1')).after(host);
  const clock=panel.querySelector('#timer-clock')??panel.querySelector('#clock');clock.classList.add('timer-clock');
  host.querySelector('#focus-clock-host').append(clock);
  mountYoutube(host);
  const select=host.querySelector('#focus-sound'),range=host.querySelector('#focus-volume'),toggle=host.querySelector('#focus-sound-toggle'),status=host.querySelector('#focus-sound-status');
  select.value=sound;range.value=volume;
  let context,source,gain,playing=false,audioBusy=false;
  const persist=()=>{try{localStorage.setItem('iw-focus-preferences',JSON.stringify({theme,sound,volume}));}catch{}};
  const paint=()=>{host.dataset.theme=theme;for(const button of host.querySelectorAll('[data-focus-theme]'))button.setAttribute('aria-pressed',String(button.dataset.focusTheme===theme));};
  const stop=()=>{source?.stop();source?.disconnect();source=null;playing=false;toggle.textContent='▶ Слушать';toggle.setAttribute('aria-pressed','false');status.textContent='Звук выключен';host.dataset.audioState='stopped';};
  async function play(){
    if(audioBusy)return;audioBusy=true;toggle.disabled=true;
    try{
      const Audio=window.AudioContext??window.webkitAudioContext;if(!Audio)throw new Error('Этот браузер не поддерживает фоновый звук.');
      if(!context||context.state==='closed'){context=new Audio();gain=null;}await context.resume();if(context.state!=='running')throw new Error('Браузер приостановил звук. Нажми «Слушать» ещё раз.');
      source?.stop();source?.disconnect();gain??=context.createGain();gain.disconnect();gain.connect(context.destination);gain.gain.setValueAtTime(volume/100*.28,context.currentTime);
      source=context.createBufferSource();source.buffer=bufferFor(context,sound);source.loop=true;source.connect(gain);source.start();playing=true;
      toggle.textContent='Ⅱ Выключить звук';toggle.setAttribute('aria-pressed','true');status.textContent=sounds[sound]+' · '+volume+'%';host.dataset.audioState='playing';
    }catch(error){stop();status.textContent=error.message;}finally{audioBusy=false;toggle.disabled=false;}
  }
  host.addEventListener('click',event=>{const button=event.target.closest('[data-focus-theme]');if(button){theme=button.dataset.focusTheme;paint();persist();}});
  toggle.addEventListener('click',()=>playing?stop():void play());
  select.addEventListener('change',()=>{sound=select.value;persist();if(playing)void play();});
  range.addEventListener('input',()=>{volume=Number(range.value);gain?.gain.setTargetAtTime(volume/100*.28,context.currentTime,.05);persist();if(playing)status.textContent=sounds[sound]+' · '+volume+'%';});
  const expand=host.querySelector('#focus-expand');
  expand.hidden=!allowExpand;
  const setExpanded=value=>{panel.classList.toggle('focus-screen',value);document.body.classList.toggle('focus-screen-active',value);expand.setAttribute('aria-pressed',String(value));expand.textContent=value?'Вернуться ↙':'Развернуть ↗';};
  expand.addEventListener('click',()=>setExpanded(!panel.classList.contains('focus-screen')));
  document.addEventListener('keydown',event=>{if(event.key==='Escape'&&panel.classList.contains('focus-screen'))setExpanded(false);});
  window.addEventListener('pagehide',()=>{stop();void context?.close();});paint();
  return {update:state=>{host.querySelector('#focus-scene-work').textContent=state.active?.title??'Выбери карточку работы';host.querySelector('#focus-scene-label').textContent=state.active?.status==='paused'?'ПАУЗА · ВРЕМЯ НЕ УЧИТЫВАЕТСЯ':state.active?'СЕЙЧАС В ФОКУСЕ':'ПРОСТРАНСТВО ДЛЯ ВАЖНОГО';}};
}
