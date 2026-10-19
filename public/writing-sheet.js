const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;

export function writingSheetUrl({id,handoff,clean=true}) {
  if(!uuid.test(id)||!uuid.test(handoff))throw new Error('Не удалось определить запись для чистого листа.');
  return `${clean?'/write':'/'}?handoff=${encodeURIComponent(handoff)}#writing/${encodeURIComponent(id)}`;
}

export function writingHandoffPost(record,{instanceId,id}) {
  const content=record?.content;
  if(!content||content.instanceId!==instanceId||content.id!==id||!uuid.test(id)
      ||!Number.isInteger(content.expectedRevision)||content.expectedRevision<0||!Array.isArray(content.document?.ops)) {
    throw new Error('Черновик относится к другой записи или архиву. Исходный текст сохранён; вернись в прежнее окно.');
  }
  return {id,revision:content.expectedRevision,title:content.title,date:content.date,status:content.status,updatedAt:record.updatedAt??null,
    favorite:content.favorite===true,document:structuredClone(content.document),trashedAt:null};
}
