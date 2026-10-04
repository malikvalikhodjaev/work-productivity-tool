import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { today, validDate } from './store.mjs';
import { replaceFile } from './atomic-file.mjs';

export function createDailyResultStore(file) {
  mkdirSync(dirname(file), { recursive: true });
  let data = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : { version: 1, entries: [] };
  if (data.version !== 1 || !Array.isArray(data.entries)) throw new Error('Неподдерживаемый формат результатов дня. Исходный файл сохранён.');
  function writeAtomic(target, value) {
    writeFileSync(`${target}.tmp`, value, 'utf8');
    replaceFile(`${target}.tmp`, target);
  }
  function view() {
    return { today: today(), entries: structuredClone(data.entries).sort((a, b) => b.date.localeCompare(a.date)) };
  }
  function syncTable() {
    const cell = value => {
      let text = String(value ?? '');
      if (/^[\s\u0000-\u001f]*[=+\-@]/.test(text)) text = `'${text}`;
      return `"${text.replaceAll('"', '""')}"`;
    };
    const rows = [['date', 'result', 'status', 'evidence', 'created_at', 'updated_at', 'edits'], ...view().entries.map(item => [item.date, item.text, item.status, item.evidence, item.createdAt, item.updatedAt, item.revisions.length])];
    writeAtomic(join(dirname(file), 'daily-results.csv'), `\uFEFF${rows.map(row => row.map(cell).join(',')).join('\r\n')}\r\n`);
  }
  function save(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Укажи результат дня.');
    if (!validDate(input.date) || input.date > today()) throw new Error('Укажи прошедшую или сегодняшнюю дату.');
    if (typeof input.text !== 'string' || !input.text.trim() || input.text.length > 2000) throw new Error('Запиши результат: от 1 до 2000 символов.');
    if (!['planned', 'ready'].includes(input.status)) throw new Error('Выбери состояние результата.');
    if (typeof input.evidence !== 'string' || input.evidence.length > 1000) throw new Error('Подтверждение: не больше 1000 символов.');
    if (input.status === 'ready' && !input.evidence.trim()) throw new Error('Укажи, какой результат получен и как проверена его готовность.');
    const previous = data.entries.find(item => item.date === input.date);
    if (input.expectedUpdatedAt !== (previous?.updatedAt ?? null)) throw new Error('Результат уже изменён. Обнови данные перед повторным сохранением.');
    const text = input.text.trim(), evidence = input.evidence.trim();
    if (previous?.text === text && previous.status === input.status && previous.evidence === evidence) return structuredClone(previous);
    const now = new Date(Math.max(Date.now(), previous ? Date.parse(previous.updatedAt) + 1 : 0)).toISOString();
    const entry = {
      date: input.date, text, status: input.status, evidence, createdAt: previous?.createdAt ?? now, updatedAt: now,
      revisions: previous ? [...previous.revisions, { text: previous.text, status: previous.status, evidence: previous.evidence, updatedAt: previous.updatedAt, replacedAt: now }] : []
    };
    const next = { ...data, entries: [...data.entries.filter(item => item.date !== entry.date), entry] };
    writeAtomic(file, `${JSON.stringify(next, null, 2)}\n`);
    data = next;
    syncTable();
    return structuredClone(entry);
  }
  if (!existsSync(file)) writeAtomic(file, `${JSON.stringify(data, null, 2)}\n`);
  syncTable();
  return { view, save };
}
