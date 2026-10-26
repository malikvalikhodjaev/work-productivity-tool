export const characteristicTypes = ['indicator','monitoring','guardrail'];
export const goalEditableFields = new Set(['title','unit','physicalSystem','baseline','target','direction','dueDate','status','trashedAt','parentId','characteristicId','workRef','characteristicType']);
const fail=(message,status=400)=>{const error=new Error(message);error.status=status;throw error;};
export function goalText(value,label,max,required=false) {
  if(typeof value!=='string'||value.length>max||required&&!value.trim())fail(`${label}: ${required?'заполни поле; ':''}не больше ${max} символов.`);
  return value;
}
export function checkedGoalType(value) {
  if(value!==null&&!characteristicTypes.includes(value))fail('Выбери тип: индикатор, мониторинг или ограничение.');
  return value;
}
export function prepareGoalFields(data,input) {
  const goal=data.goals.find(g=>g.id===input.id);
  if(!goal)fail('Характеристика не найдена.');
  if(!Array.isArray(input.changes)||!input.changes.length||input.changes.length>goalEditableFields.size)fail('Укажи изменённые поля характеристики.');
  const seen=new Set(),patch={};
  for(const change of input.changes) {
    if(!change||!goalEditableFields.has(change.field)||seen.has(change.field)||!Object.hasOwn(change,'before')||!Object.hasOwn(change,'value'))fail('Некорректная правка поля характеристики.');
    seen.add(change.field);
    if(JSON.stringify(goal[change.field]??null)!==JSON.stringify(change.before??null))fail('Это поле уже изменено на другом устройстве. Твой текст сохранён для сравнения.',409);
    patch[change.field]=change.value;
  }
  return {...goal,...patch,id:goal.id};
}
