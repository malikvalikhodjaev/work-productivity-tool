import {gridColumns,gridCellValue,gridCellText,visibleGridColumns} from './portfolio-grid-core.js';

const escape=value=>String(value ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const types={text:'Текст',number:'Число',date:'Дата',select:'Список вариантов',checkbox:'Галочка',computed:'Рассчитывается'};

export class PortfolioGrid {
  constructor(host,{table,portfolio,mutate,openRow,addRow}) {
    Object.assign(this,{host,table,portfolio,mutate,openRow,addRow});
    try {this.view=JSON.parse(localStorage.getItem(`iw-grid-view:${table}`)) ?? {};}catch {this.view={};}
    host.addEventListener('click',event=>this.click(event));
  }
  columns(archived=false){return gridColumns(this.portfolio(),this.table,{archived});}
  saveView(){localStorage.setItem(`iw-grid-view:${this.table}`,JSON.stringify(this.view));this.render(this.items);}
  render(items){
    this.items=items;
    const columns=visibleGridColumns(this.columns(),this.view);
    this.host.innerHTML=`<div class="grid-toolbar"><span>Ячейка — изменить · ↗ — открыть строку</span><div><button type="button" class="text-button" data-grid-columns>Столбцы</button><button type="button" class="text-button" data-grid-add-column>＋ Столбец</button><button type="button" class="text-button" data-grid-add-row>＋ Строка</button></div></div><div class="grid-scroll"><table class="project-table editable-grid"><thead><tr><th></th>${columns.map(c=>`<th scope="col"><button type="button" class="grid-heading" data-grid-column="${escape(c.id)}">${escape(c.title)} <small>${types[c.type]}</small></button></th>`).join('')}<th></th></tr></thead><tbody>${items.map(row=>`<tr><td><button type="button" class="text-button" aria-label="Открыть строку ${escape(row.name || row.uniqueName || row.typeName)}" data-grid-row="${escape(row.id)}">↗</button></td>${columns.map(c=>`<td>${c.type==='computed'?`<span class="grid-computed" title="Рассчитывается из альф">${escape(gridCellText(row,c))}</span>`:`<button type="button" class="grid-cell" data-grid-cell="${escape(c.id)}" data-grid-id="${escape(row.id)}">${escape(gridCellText(row,c))}</button>`}</td>`).join('')}<td><button type="button" class="text-button" data-grid-open="${escape(row.id)}">${this.table==='projects'?'Моделер':'Карточка альфы'}</button></td></tr>`).join('')}</tbody></table></div>${items.length?'':'<p class="project-empty">No Data · добавь первую строку.</p>'}`;
  }
  click(event){
    const button=event.target.closest('button');if(!button)return;
    const d=button.dataset;
    if('gridAddColumn'in d)this.columnDialog();
    else if('gridAddRow'in d)this.addRow();
    else if('gridColumns'in d)this.columnsDialog();
    else if(d.gridColumn)this.columnDialog(this.columns().find(c=>c.id===d.gridColumn));
    else if(d.gridRow)this.rowDialog(this.items.find(r=>r.id===d.gridRow));
    else if(d.gridOpen)this.openRow(this.items.find(r=>r.id===d.gridOpen));
    else if(d.gridCell)this.cellDialog(this.items.find(r=>r.id===d.gridId),this.columns().find(c=>c.id===d.gridCell));
  }
  dialog(title,body,onSave){
    const dialog=document.createElement('dialog');dialog.className='grid-dialog';
    dialog.innerHTML=`<form><h2>${escape(title)}</h2>${body}<p role="alert" class="grid-error"></p><footer><button type="button" data-close class="text-button">Закрыть</button>${onSave?'<button type="submit" class="button primary">Сохранить</button>':''}</footer></form>`;
    dialog.querySelector('[data-close]').onclick=()=>dialog.close();
    dialog.addEventListener('close',()=>dialog.remove(),{once:true});
    dialog.querySelector('form').onsubmit=async event=>{
      event.preventDefault();if(!onSave)return;
      const save=dialog.querySelector('[type=submit]');save.disabled=true;
      try {await onSave(new FormData(event.target),dialog);dialog.close();}
      catch(error){dialog.querySelector('[role=alert]').textContent=error.message;}
      finally {save.disabled=false;}
    };
    document.body.append(dialog);dialog.showModal();return dialog;
  }
  cellDialog(row,column){
    const before=gridCellValue(row,column);
    let field;
    if(column.type==='select')field=`<select name="value">${column.custom?'<option value="">No Data</option>':''}${Object.entries(column.options).map(([v,l])=>`<option value="${escape(v)}" ${v===before?'selected':''}>${escape(l)}</option>`).join('')}</select>`;
    else if(column.type==='checkbox')field=`<select name="value"><option value="">No Data</option><option value="true" ${before===true?'selected':''}>Да</option><option value="false" ${before===false?'selected':''}>Нет</option></select>`;
    else if(column.type==='text')field=`<textarea name="value" rows="7" maxlength="${column.maxLength ?? 10000}">${escape(before)}</textarea>`;
    else field=`<input name="value" type="${column.type==='number'?'number':'date'}" ${column.type==='number'?'step="any"':''} value="${escape(before)}">`;
    const dialog=this.dialog(column.title,`<p>${escape(row.name || row.uniqueName || row.typeName)}</p><label>${escape(column.title)}${field}</label>`,async form=>{
      const raw=form.get('value');let value=raw;
      if(column.type==='number')value=raw===''?null:Number(raw);
      if(column.type==='checkbox')value=raw===''?null:raw==='true';
      if(column.type==='date'&&raw==='')value=null;
      if(column.type==='select'&&raw==='')value=null;
      await this.mutate('editCells',{table:this.table,id:row.id,changes:[{columnId:column.id,before,value}]});
    });
    dialog.querySelector('[name=value]').focus();
  }
  rowDialog(row){
    const dialog=this.dialog(row.name || row.uniqueName || row.typeName || 'Строка',`<div class="grid-row-fields">${this.columns().map(c=>`<div><strong>${escape(c.title)}</strong><button type="button" data-field="${escape(c.id)}" ${c.type==='computed'?'disabled':''}>${escape(gridCellText(row,c))}</button></div>`).join('')}</div>`,null);
    dialog.addEventListener('click',event=>{const field=event.target.closest('[data-field]');if(!field)return;dialog.close();this.cellDialog(row,this.columns().find(c=>c.id===field.dataset.field));});
  }
  columnsDialog(){
    const visible=new Set(visibleGridColumns(this.columns(),this.view).map(c=>c.id));
    const dialog=this.dialog('Столбцы',`<p>Видимость и порядок сохраняются на этом устройстве. Названия своих столбцов синхронизируются.</p>${this.columns(true).map(c=>`<div class="grid-column-choice"><label><input type="checkbox" data-visible="${escape(c.id)}" ${visible.has(c.id)?'checked':''} ${c.archived?'disabled':''}>${escape(this.view.labels?.[c.id] ?? c.title)}</label><button type="button" data-config="${escape(c.id)}" class="text-button">${c.archived?'Восстановить':'Настроить'}</button></div>`).join('')}`,async(_,d)=>{
      const checked=[...d.querySelectorAll('[data-visible]:checked')].map(el=>el.dataset.visible);
      this.view.order=[...visibleGridColumns(this.columns(),this.view).map(c=>c.id),...checked.filter(id=>!visibleGridColumns(this.columns(),this.view).some(c=>c.id===id))];
      this.view.hidden=[...d.querySelectorAll('[data-visible]:not(:checked)')].map(el=>el.dataset.visible);this.saveView();
    });
    dialog.addEventListener('click',async event=>{
      const button=event.target.closest('[data-config]');if(!button)return;
      const col=this.columns(true).find(c=>c.id===button.dataset.config);
      if(col.archived){button.disabled=true;try{await this.mutate('updateColumn',{table:this.table,id:col.id,expectedRevision:col.revision,archived:false});dialog.close();this.columnsDialog();}catch(error){dialog.querySelector('[role=alert]').textContent=error.message;button.disabled=false;}}
      else {dialog.close();this.columnDialog(col);}
    });
  }
  columnDialog(column){
    const custom=!column || column.custom;
    const dialog=this.dialog(column?'Настроить столбец':'Новый столбец',`<label>Название<input name="title" required maxlength="120" value="${escape(column?(this.view.labels?.[column.id] ?? column.title):'')}"></label>${column?`<p>Тип: ${types[column.type]} · тип сохраняется, чтобы не потерять значения.</p>`:`<label>Тип<select name="type">${Object.entries(types).filter(([k])=>k!=='computed').map(([k,l])=>`<option value="${k}">${l}</option>`).join('')}</select></label><label data-options hidden>Варианты списка · каждый с новой строки<textarea name="options" rows="5"></textarea></label>`}${column?'<div class="grid-toolbar"><button type="button" data-move="-1" class="text-button">← Левее</button><button type="button" data-move="1" class="text-button">Правее →</button><button type="button" data-hide class="text-button">Скрыть</button></div>':''}${column?.custom?'<button type="button" data-archive class="text-button">Убрать столбец в архив</button>':''}`,async form=>{
      const title=form.get('title');
      if(!custom){this.view.labels={...this.view.labels,[column.id]:title};this.saveView();return;}
      if(column)await this.mutate('updateColumn',{table:this.table,id:column.id,title,expectedRevision:column.revision});
      else {const type=form.get('type'),options=Object.fromEntries(form.get('options').split('\n').map(v=>v.trim()).filter(Boolean).map(v=>[v,v]));await this.mutate('createColumn',{table:this.table,id:crypto.randomUUID(),title,type,...(type==='select'?{options}:{})});}
    });
    dialog.querySelector('[name=type]')?.addEventListener('change',event=>{dialog.querySelector('[data-options]').hidden=event.target.value!=='select';});
    dialog.querySelector('[data-hide]')?.addEventListener('click',()=>{this.view.hidden=[...(this.view.hidden ?? []),column.id];this.saveView();dialog.close();});
    for(const move of dialog.querySelectorAll('[data-move]'))move.onclick=()=>{
      const order=visibleGridColumns(this.columns(),this.view).map(c=>c.id),i=order.indexOf(column.id),j=i+Number(move.dataset.move);
      if(j>=0&&j<order.length){[order[i],order[j]]=[order[j],order[i]];this.view.order=order;this.saveView();}
    };
    dialog.querySelector('[data-archive]')?.addEventListener('click',async()=>{
      try {await this.mutate('updateColumn',{table:this.table,id:column.id,expectedRevision:column.revision,archived:true});dialog.close();}
      catch(error){dialog.querySelector('[role=alert]').textContent=error.message;}
    });
  }
}
