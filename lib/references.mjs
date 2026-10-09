import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { replaceFile } from './atomic-file.mjs';

export const referenceGroups = ['Фокус', 'Таблицы и шаблоны', 'Таймер', 'Дизайн', 'Мысли', 'Код'];
const nativeStorage = { existsSync, mkdirSync, readFileSync, writeFileSync, replaceFile };
export function createReferenceStore(file, { storage = nativeStorage } = {}) {
  const { existsSync, mkdirSync, readFileSync, writeFileSync, replaceFile } = storage;
  mkdirSync(dirname(file), { recursive: true });
  let data = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : { version: 1, entries: [] };
  if (data.version !== 1 || !Array.isArray(data.entries)) throw new Error('Неподдерживаемый формат источников. Исходный файл сохранён.');
  const atomic = (target, content) => { writeFileSync(`${target}.tmp`, content, 'utf8'); replaceFile(`${target}.tmp`, target); };
  const view = () => structuredClone({ ...data, groups: referenceGroups });
  function save(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Укажи источник или мысль.');
    if (input.id !== undefined && (typeof input.id !== 'string' || !/^[a-z0-9-]{1,100}$/.test(input.id))) throw new Error('Неверный ID источника.');
    const previous = input.id ? data.entries.find(item => item.id === input.id) : null;
    if (input.id && !previous) throw new Error('Источник не найден.');
    if (input.expectedUpdatedAt !== (previous?.updatedAt ?? null)) throw new Error('Источник уже изменён. Обнови список перед повторной правкой.');
    if (typeof input.title !== 'string' || !input.title.trim() || input.title.length > 240) throw new Error('Название: от 1 до 240 символов.');
    if (!referenceGroups.includes(input.group)) throw new Error('Выбери группу источника.');
    const fields = { title: input.title.trim(), group: input.group };
    for (const [key, max] of [['attribution', 240], ['note', 4000]]) {
      const value = input[key] ?? '';
      if (typeof value !== 'string' || value.length > max) throw new Error(`Поле ${key}: не больше ${max} символов.`);
      fields[key] = value.trim();
    }
    fields.url = input.url === undefined || input.url === null || input.url === '' ? null : input.url;
    if (fields.url !== null) {
      if (typeof fields.url !== 'string' || fields.url.length > 3000) throw new Error('Ссылка: не больше 3000 символов.');
      let url; try { url = new URL(fields.url); } catch { throw new Error('Укажи полную ссылку http:// или https://.'); }
      if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) throw new Error('Допускаются ссылки http:// и https:// без учётных данных.');
      fields.url = fields.url.trim();
    }
    if (previous && Object.entries(fields).every(([key, value]) => previous[key] === value)) return structuredClone(previous);
    const now = new Date(Math.max(Date.now(), previous ? Date.parse(previous.updatedAt) + 1 : 0)).toISOString();
    const snapshot = previous ? Object.fromEntries(Object.entries(previous).filter(([key]) => key !== 'revisions')) : null;
    const entry = { ...previous, id: previous?.id ?? randomUUID(), ...fields, originalText: previous?.originalText ?? fields.note, origin: previous?.origin ?? 'Добавлено в дашборде', createdAt: previous?.createdAt ?? now, updatedAt: now, revisions: previous ? [...(previous.revisions ?? []), { ...snapshot, replacedAt: now }] : [] };
    const next = { ...data, entries: previous ? data.entries.map(item => item.id === entry.id ? entry : item) : [...data.entries, entry] };
    atomic(file, `${JSON.stringify(next, null, 2)}\n`); data = next;
    return structuredClone(entry);
  }
  function attachment(id) {
    const entry = data.entries.find(item => item.id === id);
    if (!entry?.attachment || !/^[a-z0-9-]+\.png$/.test(entry.attachment)) return null;
    const path = join(dirname(file), 'reference-assets', entry.attachment);
    return existsSync(path) ? path : null;
  }
  if (!existsSync(file)) atomic(file, `${JSON.stringify(data, null, 2)}\n`);
  return { view, save, attachment };
}
