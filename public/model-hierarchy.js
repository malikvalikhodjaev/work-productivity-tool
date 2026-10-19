const parentOf=row=>row.parentId || null;
export function orderedSiblings(rows,parentId=null) {
  return rows.map((row,index)=>({row,index})).filter(x=>parentOf(x.row)===(parentId || null))
    .sort((a,b)=>(a.row.sortOrder ?? a.index)-(b.row.sortOrder ?? b.index)||a.index-b.index).map(x=>x.row);
}
export function hierarchySignature(rows) {
  return JSON.stringify([...rows].sort((a,b)=>a.id<b.id?-1:a.id>b.id?1:0).map(r=>[r.id,parentOf(r),r.sortOrder ?? null,r.zoneId ?? null]));
}
export function hierarchyRows(rows,collapsed=new Set()) {
  const result=[],seen=new Set(),ids=new Set(rows.map(r=>r.id));
  const visit=(row,path,depth,hidden=false)=>{
    if(seen.has(row.id))return;seen.add(row.id);
    const children=orderedSiblings(rows,row.id);
    if(!hidden)result.push({row,wbs:path,depth,hasChildren:children.length>0});
    children.forEach((child,i)=>visit(child,`${path}.${i+1}`,depth+1,hidden||collapsed.has(row.id)));
  };
  [...orderedSiblings(rows),...rows.filter(r=>parentOf(r)&&!ids.has(parentOf(r)))].forEach((row,i)=>visit(row,String(i+1),0));
  for(const row of rows)if(!seen.has(row.id))visit(row,String(result.length+1),0);
  return result;
}
export function relocateAlpha(rows,input) {
  const next=structuredClone(rows),row=next.find(r=>r.id===input.id);
  if(!row)throw new Error('Строка не найдена.');
  const parentId=input.parentId || null,oldParent=parentOf(row),parent=parentId?next.find(r=>r.id===parentId):null;
  if(parentId&&!parent)throw new Error('Родительская строка не найдена.');
  if(parent&&parent.projectId!==row.projectId)throw new Error('Родитель должен быть в том же проекте.');
  const seen=new Set([row.id]);let ancestor=parent;
  while(ancestor){if(seen.has(ancestor.id))throw new Error('Нельзя вложить строку в себя или своего потомка.');seen.add(ancestor.id);ancestor=next.find(r=>r.id===ancestor.parentId);}
  const siblings=orderedSiblings(next,parentId).filter(r=>r.id!==row.id);
  const index=input.beforeId?siblings.findIndex(r=>r.id===input.beforeId):siblings.length;
  if(index<0)throw new Error('Место вставки уже изменилось.');
  siblings.splice(index,0,row);row.parentId=parentId;
  if(parent)row.zoneId=parent.zoneId;
  const moveZone=id=>{for(const child of next.filter(r=>r.parentId===id)){child.zoneId=row.zoneId;moveZone(child.id);}};
  moveZone(row.id);
  for(const [i,sibling]of siblings.entries())sibling.sortOrder=i;
  if(oldParent!==parentId)for(const [i,sibling]of orderedSiblings(next,oldParent).entries())sibling.sortOrder=i;
  return next;
}
