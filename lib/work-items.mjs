import {randomUUID} from 'node:crypto';
export const workStages = ['note','planned','active','commissioning','blocked','ready','operation','retired'];
const text=(value,max,label,required=false)=>{if(typeof value!=='string'||value.length>max||(required&&!value.trim()))throw new Error(`${label}: ${required?'заполни; ':''}до ${max} символов.`);return value.trim();};
const conflict=message=>{const error=new Error(message);error.status=409;throw error;};
const archive=item=>Object.fromEntries(Object.entries(item).filter(([key])=>key!=='revisions'));

export function changeWorkRecords(data,action,input,{validateRef,validDate,metrics}) {
  const next=structuredClone(data), now=new Date().toISOString();
  next.workItems??=[]; next.workNotes??=[]; next.workRequests??=[];
  if(typeof input.requestId!=='string'||!/^[a-zA-Z0-9_-]{8,100}$/.test(input.requestId))throw new Error('Нужен идентификатор сохранения.');
  const signature=JSON.stringify({action,input:Object.fromEntries(Object.entries(input).filter(([key])=>key!=='requestId'))});
  const repeated=next.workRequests.find(item=>item.id===input.requestId);
  if(repeated){if(repeated.signature!==signature)conflict('Запрос уже использован для другой правки.');return {next,duplicate:true};}
  if(action==='saveWorkItem') {
    const previous=input.id?next.workItems.find(item=>item.id===input.id):null;
    if(input.id&&!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(input.id))throw new Error('Некорректный ID карточки.');
    if(input.id&&!previous&&input.create!==true)throw new Error('Карточка не найдена.');
    if(input.expectedRevision!==(previous?.revision??0))conflict('Карточка изменена в другой вкладке. Твой текст остаётся в форме; обнови карточку перед повтором.');
    if(!workStages.includes(input.stage))throw new Error('Выбери стадию работы.');
    if(!['work','issue'].includes(input.kind))throw new Error('Выбери работу или issue.');
    const projectRef=input.projectId?validateRef('project:'+input.projectId):null;
    const metricId=input.metricId??null;
    if(metricId!==null&&!metrics.some(m=>m.id===metricId&&m.unit==='hours'))throw new Error('Выбери часовой норматив.');
    const allocation=metricId?'assigned':input.allocation;
    if(!metricId&&!['outside','unclassified'].includes(allocation))throw new Error('Выбери назначение времени.');
    const reviewDate=input.reviewDate||null;
    if(reviewDate&&!validDate(reviewDate))throw new Error('Укажи корректную дату возврата.');
    const result=text(input.result??'',2000,'Результат / основание');
    if(['commissioning','ready','operation','retired'].includes(input.stage)&&!result)throw new Error('Для этой стадии запиши результат или основание.');
    let origin=previous?.origin??null;
    if(!previous&&input.origin){
      const source=input.origin;
      if(source.type!=='coda'||!['work','issues'].includes(source.table))throw new Error('Неизвестный источник карточки.');
      const sourceId=text(source.sourceId,200,'ID источника',true);
      if(next.workItems.some(item=>item.origin?.table===source.table&&item.origin?.sourceId===sourceId))conflict('Эта строка уже взята в работу. Открой существующую карточку.');
      const raw=JSON.stringify(source.snapshot);
      if(!raw||raw.length>16000)throw new Error('Слишком большой исходник карточки.');
      origin={type:'coda',table:source.table,sourceId,snapshot:structuredClone(source.snapshot),capturedAt:now};
    }
    text(input.description??'',12000,'Описание и размышления');const description=input.description??'';
    const item={...previous,id:previous?.id??input.id??randomUUID(),kind:input.kind,title:text(input.title,300,'Название',true),stage:input.stage,description,nextStep:text(input.nextStep??'',2000,'Следующий шаг'),result,projectId:projectRef?input.projectId:null,metricId,allocation,workType:text(input.workType??'',80,'Характер работы'),reviewDate,origin,originalDescription:previous?.originalDescription??description,revision:(previous?.revision??0)+1,createdAt:previous?.createdAt??now,updatedAt:now,revisions:previous?[...(previous.revisions??[]),{...archive(previous),replacedAt:now}]:[]};
    next.workItems=previous?next.workItems.map(old=>old.id===item.id?item:old):[...next.workItems,item];
  } else if(action==='saveWorkNote') {
    const workRef=validateRef(input.workRef);
    if(!workRef||!/^task:|^case:/.test(workRef))throw new Error('Выбери задачу или кейс.');
    const previous=next.workNotes.find(item=>item.workRef===workRef);
    if(input.expectedRevision!==(previous?.revision??0))conflict('Заметка изменена в другой вкладке. Твой текст остаётся в форме.');
    text(input.text??'',12000,'Размышления');
    const item={workRef,text:input.text??'',revision:(previous?.revision??0)+1,createdAt:previous?.createdAt??now,updatedAt:now,revisions:previous?[...(previous.revisions??[]),{...archive(previous),replacedAt:now}]:[]};
    next.workNotes=previous?next.workNotes.map(old=>old.workRef===workRef?item:old):[...next.workNotes,item];
  } else throw new Error('Неизвестное действие карточки.');
  next.workRequests.push({id:input.requestId,signature});next.workRequests=next.workRequests.slice(-256);
  return {next,duplicate:false};
}
