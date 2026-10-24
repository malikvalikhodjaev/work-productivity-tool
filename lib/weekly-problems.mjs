import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { today, validDate } from './store.mjs';
import { replaceFile } from './atomic-file.mjs';
import { assertNativeBase, nativeCommandGuard } from './native-commands.mjs';

export function weekStart(date = today()) {
  if (!validDate(date)) throw new Error('Укажи дату недели в формате ГГГГ-ММ-ДД.');
  const value = new Date(`${date}T00:00:00Z`);
  value.setUTCDate(value.getUTCDate() - (value.getUTCDay() + 6) % 7);
  return value.toISOString().slice(0, 10);
}

const nativeStorage = { existsSync, mkdirSync, readFileSync, writeFileSync, replaceFile };
export function createWeeklyProblemStore(file, { storage = nativeStorage, currentDate = today } = {}) {
  const { existsSync, mkdirSync, readFileSync, writeFileSync, replaceFile } = storage;
  mkdirSync(dirname(file), { recursive: true });
  let data = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : { version: 1, entries: [] };
  if (data.version !== 1 || !Array.isArray(data.entries)) throw new Error('Неподдерживаемый формат проблем недели. Исходный файл сохранён.');
  const native = nativeCommandGuard(() => data);
  function writeAtomic(target, content) {
    writeFileSync(`${target}.tmp`, content, 'utf8');
    replaceFile(`${target}.tmp`, target);
  }
  function view() {
    return { week: weekStart(currentDate()), entries: structuredClone(data.entries).sort((a, b) => b.week.localeCompare(a.week)) };
  }
  function syncTable() {
    const cell = value => {
      let text = String(value ?? '');
      if (/^[\s\u0000-\u001f]*[=+\-@]/.test(text)) text = `'${text}`;
      return `"${text.replaceAll('"', '""')}"`;
    };
    const rows = [['week_start', 'problem', 'created_at', 'updated_at', 'edits'], ...view().entries.map(e => [e.week, e.text, e.createdAt, e.updatedAt, e.revisions.length])];
    writeAtomic(join(dirname(file), 'weekly-problems.csv'), `\uFEFF${rows.map(row => row.map(cell).join(',')).join('\r\n')}\r\n`);
  }
  function save(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Укажи главную проблему недели.');
    if (!validDate(input.week) || weekStart(input.week) !== input.week || input.week > weekStart(currentDate())) throw new Error('Выбери понедельник текущей или прошедшей недели.');
    if (typeof input.text !== 'string' || !input.text.trim() || input.text.length > 2000) throw new Error('Запиши проблему: от 1 до 2000 символов.');
    const previous = data.entries.find(e => e.week === input.week);
    assertNativeBase(previous, input.expectedUpdatedAt);
    if (previous?.text === input.text) {
      const next = native.prepare(data);
      if (next !== data) { writeAtomic(file, `${JSON.stringify(next, null, 2)}\n`); data = next; }
      return structuredClone(previous);
    }
    const now = new Date(Math.max(Date.now(), previous ? Date.parse(previous.updatedAt) + 1 : 0)).toISOString();
    const entry = {
      week: input.week, text: input.text, createdAt: previous?.createdAt ?? now, updatedAt: now,
      revisions: previous ? [...previous.revisions, { text: previous.text, updatedAt: previous.updatedAt, replacedAt: now }] : [],
    };
    const next = native.prepare({ ...data, entries: [...data.entries.filter(e => e.week !== entry.week), entry] });
    writeAtomic(file, `${JSON.stringify(next, null, 2)}\n`);
    data = next;
    syncTable();
    return structuredClone(entry);
  }
  if (!existsSync(file)) writeAtomic(file, `${JSON.stringify(data, null, 2)}\n`);
  syncTable();
  function nativeSave(command) {
    if (command.action !== 'save') throw new Error('Неизвестное действие с проблемой недели.');
    native.run(command, () => save(command.input));
    return structuredClone(data.entries.find(e => e.week === command.input.week));
  }
  return { view, save, nativeSave };
}
