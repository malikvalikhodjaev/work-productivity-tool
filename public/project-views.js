const escape=value=>String(value ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const statuses={active:'Активные',paused:'Приостановлены',closed:'Закрыты'};
export class ProjectViews {
  constructor({portfolio,selected,select,mutate,grid,rerender}) {
    Object.assign(this,{portfolio,selected,select,mutate,grid,rerender});
    this.mode=localStorage.getItem('iw-project-view')==='board'?'board':'list';
    document.getElementById('project-views').addEventListener('click',event=>{
      const mode=event.target.closest('[data-project-view]');if(mode){this.mode=mode.dataset.projectView;localStorage.setItem('iw-project-view',this.mode);this.render();}
      if(event.target.closest('[data-template-new]'))this.copyDialog();
      if(event.target.closest('[data-copy-selected]'))this.copyDialog(this.selected());
    });
    const board=document.getElementById('project-board');
    board.addEventListener('click',event=>{
      const open=event.target.closest('[data-board-project]');if(open)this.select(this.portfolio().projects.find(p=>p.id===open.dataset.boardProject));
      const copy=event.target.closest('[data-board-copy]');if(copy)this.copyDialog(this.portfolio().projects.find(p=>p.id===copy.dataset.boardCopy));
    });
    board.addEventListener('change',async event=>{
      const control=event.target.closest('[data-board-status]');if(!control)return;
      const row=this.portfolio().projects.find(p=>p.id===control.dataset.boardStatus);control.disabled=true;
      try{await this.mutate('editCells',{table:'projects',id:row.id,changes:[{columnId:'status',before:row.status,value:control.value}]});}
      catch(error){control.value=row.status;document.getElementById('portfolio-error-text').textContent=error.message;document.getElementById('portfolio-error').hidden=false;control.disabled=false;}
    });
  }
  render(){
    const portfolio=this.portfolio();if(!portfolio)return;
    document.getElementById('project-list').hidden=this.mode!=='list';
    const board=document.getElementById('project-board');board.hidden=this.mode!=='board';
    document.querySelectorAll('[data-project-view]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.projectView===this.mode)));
    document.querySelector('[data-copy-selected]').disabled=!this.selected();
    document.getElementById('modeler-workspace').hidden=!this.selected();
    if(this.mode!=='board')return;
    board.innerHTML=Object.entries(statuses).map(([id,title])=>{
      const projects=portfolio.projects.filter(p=>p.status===id);
      return `<section class="project-lane" aria-label="${title}"><h3>${title} <span>${projects.length}</span></h3>${projects.map(p=>`<article class="project-board-card ${this.selected()?.id===p.id?'selected':''}"><button type="button" data-board-project="${escape(p.id)}" aria-pressed="${this.selected()?.id===p.id}">${escape(p.name)}</button><p>${p.phase==='operation'?'В эксплуатации':'До эксплуатации'} · альф: ${p.summary.filled} / ${p.summary.slots}</p><p>Зон с пробелами: ${p.summary.gaps}</p><label>Состояние<select data-board-status="${escape(p.id)}">${Object.entries(statuses).map(([value,label])=>`<option value="${value}" ${value===p.status?'selected':''}>${label}</option>`).join('')}</select></label><button type="button" class="text-button" data-board-copy="${escape(p.id)}">Копировать структуру</button></article>`).join('') || '<p class="project-empty">Не записано</p>'}</section>`;
    }).join('');
  }
  copyDialog(source=null){
    const portfolio=this.portfolio(),catalog=portfolio.projectTemplates ?? [];
    if(!source&&!catalog.length){this.grid.dialog('Шаблоны проектов',`<p>пакет шаблонов недоступен.</p><p>${escape(portfolio.templateError ?? 'Загрузи свой справочник альф в локальные источники.')}</p>`,null);return;}
    const projectDefinition=source?{id:source.id,version:source.copyVersion,capturedAt:source.updatedAt,areas:source.zones,alphas:portfolio.alphas.filter(a=>a.projectId===source.id).map(a=>({sourceId:a.id,areaId:a.zoneId}))}:null;
    let definition=projectDefinition || catalog[0];
    const clientId=crypto.randomUUID(),ids=new Map();
    for(const d of (projectDefinition?[projectDefinition]:catalog))for(const a of d.alphas)ids.set(a.sourceId,crypto.randomUUID());
    const dialog=this.grid.dialog(source?'Копировать структуру проекта':'Новый проект из шаблона',`<label>Название проекта<input name="name" required maxlength="120" value="${escape(source?source.name+' · копия':'')}"></label>${source?`<p>Источник: ${escape(source.name)}</p>`:`<label>Набор<select name="template">${catalog.map(t=>`<option value="${escape(t.id)}">${escape(t.title)}</option>`).join('')}</select></label>`}<p data-template-date></p><p>Копируется структура и подсказки. Факты, время, проектные имена и подтверждённые состояния не переносятся.</p><fieldset data-template-areas><legend>Области интересов</legend></fieldset><p data-template-count></p>`,async form=>{
      const areaIds=form.getAll('area'),nodes=definition.alphas.filter(a=>areaIds.includes(a.areaId));
      const result=await this.mutate('copyProject',{clientId,name:form.get('name'),expectedVersion:definition.version,areaIds,alphaIds:Object.fromEntries(nodes.map(a=>[a.sourceId,ids.get(a.sourceId)])),...(source?{sourceProjectId:source.id}:{templateId:definition.id})});
      await this.select(result.projects.find(p=>p.id===clientId));
    });
    const count=()=>{const selected=[...dialog.querySelectorAll('[name=area]:checked')].map(c=>c.value);dialog.querySelector('[data-template-count]').textContent=`Будет создано альф и подальф: ${definition.alphas.filter(a=>selected.includes(a.areaId)).length}. Заполнено: 0.`;};
    const populate=()=>{
      dialog.querySelector('[data-template-date]').textContent=source?'Независимая копия выбранной структуры':`Сохранённый пакет · ${definition.capturedAt || 'Не записано'} · ${definition.areas.length} областей`;
      dialog.querySelector('[data-template-areas]').innerHTML='<legend>Области интересов</legend>'+definition.areas.map(a=>`<label class="grid-column-choice"><span>${escape(a.title)}</span><input type="checkbox" name="area" value="${escape(a.id)}" checked></label>`).join('');count();
    };
    dialog.querySelector('[name=template]')?.addEventListener('change',event=>{definition=catalog.find(t=>t.id===event.target.value);populate();});
    dialog.querySelector('[data-template-areas]').addEventListener('change',count);populate();
  }
}
