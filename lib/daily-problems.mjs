import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { today, validDate } from './store.mjs';
import { replaceFile } from './atomic-file.mjs';

export function createDailyProblemStore(file) {
  mkdirSync(dirname(file), { recursive: true });
  let data = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : { version: 1, entries: [] };
  if (data.version !== 1 || !Array.isArray(data.entries)) throw new Error('Неподдерживаемый формат проблем дня. Исходный файл сохранён.');

  function writeAtomic(target, content) {
    writeFileSync(`${target}.tmp`, content, 'utf8');
    replaceFile(`${target}.tmp`, target);
  }

  function syncTable() {
    const cell = value => {
      let text = String(value ?? '');
      if (/^[\s\u0000-\u001f]*[=+\-@]/.test(text)) text = `'${text}`;
      return `"${text.replaceAll('"', '""')}"`;
    };
    const rows = [['date', 'problem', 'created_at', 'updated_at', 'edits'], ...view().entries.map(item => [item.date, item.text, item.createdAt, item.updatedAt, item.revisions.length])];
    writeAtomic(join(dirname(file), 'daily-problems.csv'), `\uFEFF${rows.map(row => row.map(cell).join(',')).join('\r\n')}\r\n`);
  }

  function view() {
    return { today: today(), entries: structuredClone(data.entries).sort((a, b) => b.date.localeCompare(a.date)) };
  }

  function save(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Укажи проблему дня.');
    if (!validDate(input.date) || input.date > today()) throw new Error('Укажи прошедшую или сегодняшнюю дату.');
    if (typeof input.text !== 'string' || !input.text.trim() || input.text.length > 2000) throw new Error('Запиши проблему: от 1 до 2000 символов.');
    const previous = data.entries.find(item => item.date === input.date);
    if (input.expectedUpdatedAt !== (previous?.updatedAt ?? null)) throw new Error('Запись уже изменена. Обнови строку и сохрани свою формулировку ещё раз.');
    const text = input.text.trim();
    if (previous?.text === text) return structuredClone(previous);
    const now = new Date(Math.max(Date.now(), previous ? Date.parse(previous.updatedAt) + 1 : 0)).toISOString();
    const entry = {
      date: input.date, text, createdAt: previous?.createdAt ?? now, updatedAt: now,
      revisions: previous ? [...previous.revisions, { text: previous.text, updatedAt: previous.updatedAt, replacedAt: now }] : []
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
