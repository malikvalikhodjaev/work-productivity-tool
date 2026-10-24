export function checkedParent(rows, id, value) {
  const parentId = value === '' || value === undefined ? null : value;
  if (parentId !== null && typeof parentId !== 'string') throw new Error('Выбери родительский объект.');
  const seen = new Set([id]);
  let cursor = parentId;
  while (cursor) {
    if (seen.has(cursor)) throw new Error('Нельзя вложить объект в себя или своего потомка.');
    seen.add(cursor);
    const parent = rows.find(r => r.id === cursor);
    if (!parent) throw new Error('Родительский объект не найден.');
    cursor = parent.parentId;
  }
  return parentId;
}
