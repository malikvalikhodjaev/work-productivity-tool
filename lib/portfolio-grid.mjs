import {randomUUID} from 'node:crypto';
import {gridColumns,gridCellValue,portfolioGridColumns} from '../public/portfolio-grid-core.js';
import {nativeId} from './native-commands.mjs';

const ownObject = value => value && typeof value === 'object' && !Array.isArray(value);
const equal = (a,b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
const fail = (message,status=400) => {const error=new Error(message);error.status=status;throw error;};
const scalarTypes = ['text','number','date','select','checkbox'];

export function checkedGridValue(value,column,validDate) {
  if (value === null || value === '') {
    if (column.required || column.type === 'select' && !column.custom) fail(`«${column.title}»: выбери или заполни значение.`);
    return value;
  }
  if (column.type === 'text' && (typeof value !== 'string' || value.length > (column.maxLength ?? 10000))) fail(`«${column.title}»: текст до ${column.maxLength ?? 10000} символов.`);
  if (column.required && typeof value === 'string' && !value.trim()) fail(`«${column.title}»: заполни значение.`);
  if (column.type === 'number' && (typeof value !== 'number' || !Number.isFinite(value))) fail(`«${column.title}»: укажи число.`);
  if (column.type === 'checkbox' && typeof value !== 'boolean') fail(`«${column.title}»: нужно да или нет.`);
  if (column.type === 'date' && (typeof value !== 'string' || !validDate(value))) fail(`«${column.title}»: укажи корректную дату.`);
  if (column.type === 'select' && (typeof value !== 'string' || !Object.hasOwn(column.options ?? {},value))) fail(`«${column.title}»: выбери значение из списка.`);
  return value;
}

export function checkedCustomValues(value,columns,validDate) {
  if (value === undefined) return undefined;
  if (!ownObject(value) || Object.keys(value).length > 100) fail('Некорректные дополнительные поля.');
  for (const [id,item] of Object.entries(value)) {
    const column=columns.find(c=>c.id===id&&c.custom);
    if (!column) fail('Для дополнительного поля не найден столбец.');
    checkedGridValue(item,column,validDate);
  }
  return structuredClone(value);
}

export function applyPortfolioGrid(portfolio,action,input,validDate,changePortfolio) {
  const table=input.table;
  if (!portfolioGridColumns[table]) fail('Неизвестная таблица.');
  if (action === 'editCells') {
    const previous=portfolio[table].find(row=>row.id===input.id);
    if (!previous) fail('Строка не найдена.');
    if (!Array.isArray(input.changes) || !input.changes.length || input.changes.length > 100) fail('Выбери ячейки для изменения.');
    const columns=gridColumns(portfolio,table), seen=new Set();
    const candidate=structuredClone(previous);
    for (const change of input.changes) {
      const column=columns.find(c=>c.id===change.columnId);
      if (!column || column.type==='computed' || seen.has(column.id)) fail('Этот столбец рассчитывается или недоступен для изменения.');
      seen.add(column.id);
      if (!Object.hasOwn(change,'before') || !equal(gridCellValue(previous,column),change.before)) fail(`Ячейка «${column.title}» уже изменена. Твоя правка сохранена; сверим значения.`,409);
      const value=checkedGridValue(change.value,column,validDate);
      if (column.custom) {candidate.customValues ??= {};candidate.customValues[column.id]=value;}
      else candidate[column.id]=value;
    }
    const result=changePortfolio(portfolio,table==='projects'?'updateProject':'updateAlpha',{
      ...candidate,
      ...(table==='projects'?{zoneIds:candidate.zones.map(z=>z.id)}:{}),
    },validDate);
    const row=result[table].find(r=>r.id===input.id);
    // Validation above does not authorize trimming or replacing the owner's cell text.
    for (const column of columns) if(!column.custom && column.type!=='computed' && Object.hasOwn(candidate,column.id)) row[column.id]=candidate[column.id];
    if (candidate.customValues) row.customValues=candidate.customValues;
    result.tableHistory=[...(portfolio.tableHistory ?? []),{id:randomUUID(),table,rowId:row.id,at:row.updatedAt,changes:structuredClone(input.changes)}];
    return result;
  }
  const next=structuredClone(portfolio);
  next.tableColumns ??= {};
  const columns=next.tableColumns[table] ??= [];
  if (action === 'createColumn') {
    if (columns.length >= 100) fail('В таблице уже 100 дополнительных столбцов.');
    if (!nativeId(input.id) || columns.some(c=>c.id===input.id)) fail('Нужен новый UUID столбца.');
    if (!scalarTypes.includes(input.type)) fail('Выбери тип столбца.');
    const title=columnTitle(input.title);
    if (gridColumns(next,table,{archived:true}).some(c=>c.title.toLocaleLowerCase('ru')===title.toLocaleLowerCase('ru'))) fail('Столбец с таким названием уже есть.');
    const options=input.type==='select'?columnOptions(input.options):undefined;
    const now=new Date().toISOString();
    columns.push({id:input.id,title,type:input.type,custom:true,visible:true,archived:false,revision:1,createdAt:now,updatedAt:now,...(options?{options}:{})});
  } else if (action === 'updateColumn') {
    const column=columns.find(c=>c.id===input.id);
    if (!column) fail('Дополнительный столбец не найден.');
    if (input.expectedRevision!==column.revision) fail('Настройки столбца уже изменены. Сохрани свой текст и обнови таблицу.',409);
    const before=structuredClone(column);delete before.revisions;
    const title=columnTitle(input.title ?? column.title);
    if (gridColumns(next,table,{archived:true}).some(c=>c.id!==column.id&&c.title.toLocaleLowerCase('ru')===title.toLocaleLowerCase('ru'))) fail('Столбец с таким названием уже есть.');
    if (input.archived!==undefined&&typeof input.archived!=='boolean') fail('Некорректное состояние столбца.');
    Object.assign(column,{title,archived:input.archived ?? column.archived,revision:column.revision+1,updatedAt:new Date().toISOString()});
    column.revisions=[...(column.revisions ?? []),before];
  } else fail('Неизвестное действие с таблицей.');
  return next;
}

function columnTitle(value) {
  if (typeof value!=='string'||!value.trim()||value.length>120) fail('Название столбца: от 1 до 120 символов.');
  return value.trim();
}
function columnOptions(value) {
  if (!ownObject(value)||!Object.keys(value).length||Object.keys(value).length>100||Object.entries(value).some(([key,label])=>!key.trim()||key.length>120||typeof label!=='string'||!label.trim()||label.length>120)) fail('Задай от 1 до 100 значений списка.');
  return structuredClone(value);
}

export function checkTableColumns(value) {
  if (value===undefined) return {};
  if (!ownObject(value)||Object.keys(value).some(k=>!portfolioGridColumns[k])) fail('Некорректная схема таблиц.');
  const result={};
  for (const table of Object.keys(value)) {
    if (!Array.isArray(value[table])||value[table].length>100) fail('Некорректный список столбцов.');
    const ids=new Set();
    result[table]=value[table].map(column=>{
      if (!column||!nativeId(column.id)||ids.has(column.id)||!scalarTypes.includes(column.type)||column.custom!==true||typeof column.archived!=='boolean'||!Number.isInteger(column.revision)||column.revision<1) fail('Некорректный дополнительный столбец.');
      ids.add(column.id);columnTitle(column.title);
      if(column.type==='select')columnOptions(column.options);
      return structuredClone(column);
    });
  }
  return result;
}
