// Canonical CSV contract. Source app adapters are added only against real samples.
export function parseFinanceCsv(text) {
  if (typeof text !== 'string' || !text.trim()) throw new Error('Выбери непустой CSV-файл в UTF-8.');
  text = text.replace(/^\uFEFF/, '');
  const firstLine = text.split(/\r?\n/)[0];
  const delimiter = firstLine.includes(';') ? ';' : ',';
  const rows = [];
  let row = [], cell = '', quoted = false, closed = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { cell += '"'; i++; } else { quoted = false; closed = true; }
      } else cell += c;
    } else if (c === '"') {
      if (cell || closed) throw new Error('Некорректные кавычки CSV.');
      quoted = true;
    } else if (c === delimiter || c === '\n' || c === '\r') {
      row.push(cell); cell = ''; closed = false;
      if (c !== delimiter) { if (row.some(x => x !== '')) rows.push(row); row = []; if (c === '\r' && text[i + 1] === '\n') i++; }
    } else { if (closed) throw new Error('Лишний текст после кавычек CSV.'); cell += c; }
  }
  if (quoted) throw new Error('Незакрытые кавычки CSV.');
  row.push(cell); if (row.some(x => x !== '')) rows.push(row);
  const headers = rows.shift()?.map(h => h.trim()) ?? [];
  if (new Set(headers).size !== headers.length) throw new Error('Заголовки CSV не должны повторяться.');
  for (const key of ['externalId', 'date', 'amount', 'currency', 'type']) if (!headers.includes(key)) throw new Error(`Нет колонки ${key}. Формат: externalId,date,amount,currency,type,category,description.`);
  return rows.map((cells, i) => {
    if (cells.length !== headers.length) throw new Error(`Строка ${i + 2}: число колонок отличается от заголовка.`);
    const item = Object.fromEntries(headers.map((h, j) => [h, cells[j]]));
    if (!/^\d+(?:[.,]\d{1,2})?$/.test(item.amount.trim())) throw new Error(`Строка ${i + 2}: некорректная сумма.`);
    item.amount = Number(item.amount.trim().replace(',', '.'));
    return item;
  });
}
