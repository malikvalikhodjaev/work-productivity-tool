import {checkedParent} from './entity-hierarchy.mjs';

const parent = row => row.parentId || null;
export const goalHierarchySignature = rows => JSON.stringify([...rows]
  .sort((a,b)=>a.id<b.id?-1:a.id>b.id?1:0)
  .map(r=>[r.id,parent(r),r.sortOrder??null,r.status==='archived',r.trashedAt??null]));
const fail = message => {const e=new Error(message);e.status=409;throw e;};
export function goalSiblings(rows,parentId=null) {
  return rows.map((row,index)=>({row,index})).filter(x=>parent(x.row)===parentId)
    .sort((a,b)=>(a.row.sortOrder??a.index)-(b.row.sortOrder??b.index)||a.index-b.index).map(x=>x.row);
}
export function relocateGoal(rows,input) {
  const next=structuredClone(rows),row=next.find(r=>r.id===input.id);
  if(!row)fail('Строка не найдена. Исходное перемещение сохранено.');
  const parentId=checkedParent(next,row.id,input.parentId),oldParent=parent(row);
  const available = id => {
    const seen=new Set();
    while(id) {
      if(seen.has(id))fail('В структуре обнаружен цикл.');
      seen.add(id);const current=next.find(r=>r.id===id);
      if(!current||current.trashedAt||current.status==='archived')fail('Сначала восстанови ветвь из архива или корзины.');
      id=parent(current);
    }
  };
  available(row.id);available(parentId);
  const siblings=goalSiblings(next,parentId).filter(r=>r.id!==row.id);
  const index=input.beforeId==null?siblings.length:siblings.findIndex(r=>r.id===input.beforeId);
  if(index<0)fail('Место вставки уже изменилось. Обнови таблицу.');
  if(input.beforeId!=null)available(input.beforeId);
  siblings.splice(index,0,row);row.parentId=parentId;
  siblings.forEach((r,i)=>{r.sortOrder=i;});
  if(oldParent!==parentId)goalSiblings(next,oldParent).forEach((r,i)=>{r.sortOrder=i;});
  return next;
}
