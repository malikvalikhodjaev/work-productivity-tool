import {createHash} from 'node:crypto';
import {existsSync,readFileSync,statSync} from 'node:fs';
import {nativeId} from './native-commands.mjs';

const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const alphaRow=row=>/— (подальфа|альфа)$/.test(row.level ?? '');
const fail=(message,status=400)=>{const error=new Error(message);error.status=status;throw error;};
export function compileReferenceTemplate(pack) {
  if(!pack?.rows?.length)return null;
  if(!Array.isArray(pack.rows)||pack.rows.length>3000)fail('В пакете шаблона слишком много строк.');
  const rows=pack.rows,byId=new Map();
  for(const row of rows){if(typeof row.sourceId!=='string'||byId.has(row.sourceId))fail('В пакете есть повтор или отсутствующий ID строки.');byId.set(row.sourceId,row);}
  const definitions=rows.filter(alphaRow),definitionIds=new Set(definitions.map(r=>r.sourceId));
  if(!definitions.length)return null;
  const areas=[...new Set(definitions.map(r=>r.area))].map((title,index)=>{
    if(typeof title!=='string'||!title.trim()||title.length>100)fail('Некорректная область интересов в шаблоне.');
    return {id:`area-${index+1}`,title};
  });
  const nearest=(row,requireAlpha=true)=>{
    const seen=new Set([row.sourceId]);let cursor=byId.get(row.parentId);
    while(cursor){if(seen.has(cursor.sourceId))fail('В пакете шаблона есть цикл.');seen.add(cursor.sourceId);if(!requireAlpha||definitionIds.has(cursor.sourceId))return cursor.sourceId;cursor=byId.get(cursor.parentId);}
    return null;
  };
  const alphas=definitions.map(row=>{
    if(typeof row.alpha!=='string'||!row.alpha.trim()||row.alpha.length>120)fail('В шаблоне есть некорректное название альфы.');
    const states=rows.filter(r=>r.state&&nearest(r)===row.sourceId).map(state=>({sourceId:state.sourceId,title:state.state,questions:rows.filter(r=>r.question&&nearest(r,false)===state.sourceId).map(q=>({sourceId:q.sourceId,text:q.question}))}));
    const questions=rows.filter(r=>r.question&&nearest(r)===row.sourceId&&!states.some(s=>s.questions.some(q=>q.sourceId===r.sourceId))).map(q=>({sourceId:q.sourceId,text:q.question}));
    return {sourceId:row.sourceId,parentId:nearest(row),areaId:areas.find(a=>a.title===row.area).id,typeName:row.alpha,states,questions};
  });
  return {id:'meta-alpha-reference',title:'Мета-альфы из руководств',version:hash({rows,sources:pack.sources ?? {}}),capturedAt:pack.capturedAt ?? null,sources:structuredClone(pack.sources ?? {}),areas,alphas,sourceRows:structuredClone(rows)};
}
export function referenceTemplateReader(file){
  let stamp=null,cached=[];
  return ()=>{if(!existsSync(file))return [];const next=statSync(file);const signature=`${next.mtimeMs}:${next.size}`;if(stamp!==signature){const template=compileReferenceTemplate(JSON.parse(readFileSync(file,'utf8')));cached=template?[template]:[];stamp=signature;}return cached;};
}
export const publicProjectTemplate=template=>{const {sourceRows,...view}=template;return structuredClone(view);};
export const projectCopyVersion=(project,alphas)=>hash({project,alphas});

export function projectDefinition(project,alphas) {
  return {id:project.id,version:projectCopyVersion(project,alphas),capturedAt:project.updatedAt ?? null,
    areas:project.zones.map(z=>({id:z.id,title:z.title,hint:z.hint ?? '',typeName:z.typeName ?? z.title})),
    alphas:alphas.map(a=>({sourceId:a.id,parentId:a.parentId || null,areaId:a.zoneId,typeName:a.typeName || a.uniqueName,sortOrder:a.sortOrder,states:structuredClone(a.templateStates ?? []),questions:structuredClone(a.templateQuestions ?? []),source:a.source ?? ''})),
    sources:project.templateOrigin?.sources ?? {}};
}
export function materializeProject(definition,input,existingIds=new Set()) {
  if(!nativeId(input.clientId)||existingIds.has(input.clientId))fail('Нужен новый UUID проекта.');
  if(typeof input.name!=='string'||!input.name.trim()||input.name.length>120)fail('Назови новый проект: до 120 символов.');
  const selected=input.areaIds ?? definition.areas.map(a=>a.id);
  if(!Array.isArray(selected)||!selected.length||selected.some(id=>!definition.areas.some(a=>a.id===id)))fail('Выбери области интересов из шаблона.');
  const areas=definition.areas.filter(a=>selected.includes(a.id)),nodes=definition.alphas.filter(a=>selected.includes(a.areaId));
  for(const node of definition.alphas){
    const seen=new Set([node.sourceId]);let cursor=node;
    if(typeof node.typeName!=='string'||!node.typeName.trim()||node.typeName.length>120)fail('Назови тип альфы в исходной структуре: до 120 символов.');
    while(cursor.parentId){const parent=definition.alphas.find(a=>a.sourceId===cursor.parentId);if(!parent||parent.areaId!==node.areaId||seen.has(parent.sourceId))fail('В шаблоне нарушена иерархия или связь с областью интересов.');seen.add(parent.sourceId);cursor=parent;}
  }
  const ids=input.alphaIds;
  if(!ids||typeof ids!=='object'||Array.isArray(ids)||Object.keys(ids).length!==nodes.length)fail('Не совпадает набор строк шаблона.');
  const used=new Set([...existingIds,input.clientId]);
  for(const node of nodes){const id=ids[node.sourceId];if(!nativeId(id)||used.has(id))fail('Некорректный или повторный UUID строки.');used.add(id);}
  const now=new Date().toISOString();
  const origin={id:definition.id,version:definition.version,capturedAt:definition.capturedAt,sources:structuredClone(definition.sources),areaIds:[...selected]};
  const project={id:input.clientId,name:input.name,status:'active',phase:'pre_operation',revision:1,zones:areas.map(a=>({id:a.id,title:a.title,hint:a.hint ?? '',typeName:a.typeName ?? a.title})),createdAt:now,updatedAt:now,templateOrigin:origin};
  const alphas=nodes.map((node,index)=>({id:ids[node.sourceId],projectId:project.id,parentId:node.parentId&&ids[node.parentId]?ids[node.parentId]:null,zoneId:node.areaId,
    typeName:node.typeName,uniqueName:'',description:'',state:'empty',stateLabel:'',criteria:'',evidence:'',nextStep:'',filledDate:null,reviewDate:null,
    area:areas.find(a=>a.id===node.areaId).title,source:node.source ?? definition.sources?.catalog ?? definition.sources?.template ?? '',
    sortOrder:node.sortOrder ?? index,templateStates:structuredClone(node.states ?? []),templateQuestions:structuredClone(node.questions ?? []),templateOrigin:{...origin,sourceRowId:node.sourceId},createdAt:now,updatedAt:now}));
  return {project,alphas};
}

export function validateAlphaTemplateFields(row) {
  if(row.sortOrder!==undefined&&(!Number.isFinite(row.sortOrder)||Math.abs(row.sortOrder)>1000000))fail('Некорректный порядок строки.');
  for(const key of ['templateStates','templateQuestions'])if(row[key]!==undefined) {
    if(!Array.isArray(row[key])||row[key].length>1000)fail('Некорректные подсказки шаблона.');
    for(const item of row[key]){
      if(!item||typeof item.sourceId!=='string'||item.sourceId.length>200||typeof (key==='templateStates'?item.title:item.text)!=='string'||(key==='templateStates'?item.title:item.text).length>4000)fail('Некорректная строка подсказки.');
      if(key==='templateStates')validateAlphaTemplateFields({templateQuestions:item.questions});
    }
  }
  if(row.templateOrigin!==undefined&&(!row.templateOrigin||typeof row.templateOrigin!=='object'||Array.isArray(row.templateOrigin)||JSON.stringify(row.templateOrigin).length>10000))fail('Некорректный источник шаблона.');
}

export function copyPortfolioProject(portfolio,input,getTemplates) {
  let definition;
  if(input.templateId){
    definition=getTemplates().find(t=>t.id===input.templateId);
    if(!definition)fail('Пакет шаблонов сейчас недоступен.');
    if(input.expectedVersion!==definition.version)fail('Пакет шаблонов изменился. Открой выбор шаблона заново.',409);
  }else{
    const source=portfolio.projects.find(p=>p.id===input.sourceProjectId);
    if(!source)fail('Исходный проект не найден.');
    definition=projectDefinition(source,portfolio.alphas.filter(a=>a.projectId===source.id));
    if(input.expectedVersion!==definition.version)fail('Исходный проект изменился. Обнови его перед копированием.',409);
  }
  const existing=new Set([...portfolio.projects,...portfolio.alphas,...portfolio.tasks].map(r=>r.id));
  const {project,alphas}=materializeProject(definition,input,existing),next=structuredClone(portfolio);
  next.projects.push(project);next.alphas.push(...alphas);
  if(definition.sourceRows){next.templateVersions ??= {};next.templateVersions[definition.version] ??= {...publicProjectTemplate(definition),sourceRows:structuredClone(definition.sourceRows)};}
  return next;
}
