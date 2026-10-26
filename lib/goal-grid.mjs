import {randomUUID} from 'node:crypto';
import {nativeId} from './native-commands.mjs';
import {checkedGridValue} from './portfolio-grid.mjs';

export const goalBaseColumns = [
  {id:'title',title:'Характеристика',type:'text',width:400},
  {id:'characteristicType',title:'Тип',type:'select',width:220,options:{indicator:'Индикатор',monitoring:'Мониторинг',guardrail:'Ограничение (guardrail)'}},
  {id:'physicalSystem',title:'Физическая система',type:'text',width:240},
  {id:'unit',title:'Единица / период',type:'text',width:200},
  {id:'current',title:'Шкала/характеристика сейчас',type:'computed',width:240},
  {id:'target',title:'Предпочтительная мною шкала',type:'number',width:240},
  {id:'delta',title:'Изменение',type:'computed',width:260},
  {id:'dueDate',title:'Дедлайн цели',type:'date',width:200},
  {id:'status',title:'Статус цели',type:'select',width:220},
];
const fail=(message,status=400)=>{const error=new Error(message);error.status=status;throw error;};
const object=value=>value&&typeof value==='object'&&!Array.isArray(value);
const title=value=>{if(typeof value!=='string'||!value.trim()||value.length>120)fail('Название столбца: 1–120 символов.');return value;};
export function goalGridColumns(data,{archived=false}={}) {
  const overrides=new Map((data.goalColumns??[]).map(c=>[c.id,c]));
  return [...goalBaseColumns.map(c=>({...c,revision:0,...overrides.get(c.id),custom:false})),
    ...(data.goalColumns??[]).filter(c=>c.custom===true)].filter(c=>archived||!c.archived);
}
export function changeGoalGrid(data,action,input,validDate) {
  const next=structuredClone(data),at=new Date().toISOString();
  next.goalColumns??=[];next.goalTableHistory??=[];
  const all=goalGridColumns(next,{archived:true});
  if(action==='editGoalCell') {
    const goal=next.goals.find(g=>g.id===input.id);
    const column=all.find(c=>c.id===input.columnId&&c.custom&&!c.archived);
    if(!goal||!column)fail('Строка или дополнительный столбец недоступны.');
    const before=goal.customValues?.[column.id]??null;
    if(!Object.hasOwn(input,'before')||JSON.stringify(before)!==JSON.stringify(input.before??null))fail('Ячейка уже изменилась. Локальная правка сохранена для разбора.',409);
    const value=checkedGridValue(input.value,column,validDate);
    goal.customValues={...goal.customValues,[column.id]:value};
    next.goalTableHistory.push({id:randomUUID(),at,rowId:goal.id,columnId:column.id,before,value});
    return next;
  }
  const label=title(input.title);
  if(all.some(c=>c.id!==input.id&&c.title.trim().toLocaleLowerCase('ru')===label.trim().toLocaleLowerCase('ru')))fail('Столбец с таким названием уже есть.');
  if(action==='createGoalColumn') {
    if(!nativeId(input.id)||all.some(c=>c.id===input.id))fail('Нужен новый UUID столбца.');
    if(next.goalColumns.filter(c=>c.custom).length>=100)fail('Уже создано 100 дополнительных столбцов.');
    if(!['text','number','date','checkbox','select'].includes(input.type))fail('Выбери тип столбца.');
    if(input.type==='select'&&(!object(input.options)||!Object.keys(input.options).length||Object.keys(input.options).length>100||Object.entries(input.options).some(([key,value])=>!key.trim()||key.length>120||typeof value!=='string'||!value.trim()||value.length>120)))fail('Задай варианты списка: 1–100 значений.');
    const column={id:input.id,title:label,type:input.type,custom:true,archived:false,revision:1,width:200,createdAt:at,updatedAt:at,...(input.type==='select'?{options:structuredClone(input.options)}:{})};
    next.goalColumns.push(column);next.goalTableHistory.push({id:randomUUID(),at,columnId:column.id,before:null,value:column});
  } else if(action==='updateGoalColumn') {
    const previous=all.find(c=>c.id===input.id);
    if(!previous)fail('Столбец не найден.');
    if(input.expectedRevision!==previous.revision)fail('Название столбца изменилось на другом устройстве. Локальный текст сохранён.',409);
    if(input.archived!==undefined&&(!previous.custom||typeof input.archived!=='boolean'))fail('Архивировать можно только свой столбец.');
    const column={...previous,title:label,revision:previous.revision+1,updatedAt:at,archived:input.archived??previous.archived??false};
    const index=next.goalColumns.findIndex(c=>c.id===column.id);
    if(index<0)next.goalColumns.push(column);else next.goalColumns[index]=column;
    next.goalTableHistory.push({id:randomUUID(),at,columnId:column.id,before:previous,value:column});
  } else fail('Неизвестная команда столбца индикаторов.');
  return next;
}
