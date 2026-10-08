import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { today, validDate } from './store.mjs';
import { replaceFile } from './atomic-file.mjs';

export function createDailyResultStore(file, { validateWorkRef = ref => { if (ref) throw new Error('Связанный объект недоступен.'); return null; } } = {}) {
  mkdirSync(dirname(file), { recursive: true });
  let data = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : { version: 1, entries: [] };
  if (data.version !== 1 || !Array.isArray(data.entries)) throw new Error('Неподдерживаемый формат результатов дня. Исходный файл сохранён.');
  function writeAtomic(target, value) {
    writeFileSync(`${target}.tmp`, value, 'utf8');
    replaceFile(`${target}.tmp`, target);
  }
  function view() {
    return { today: today(), entries: structuredClone(data.entries).map(item => ({ ...item, progress: item.status === 'ready' ? 100 : item.progress ?? null, workRef: item.workRef ?? null, whyImportant: item.whyImportant ?? '', nextStep: item.nextStep ?? '', focusWindow: item.focusWindow ?? '' })).sort((a, b) => b.date.localeCompare(a.date)) };
  }
  function syncTable() {
    const cell = value => {
      let text = String(value ?? '');
      if (/^[\s\u0000-\u001f]*[=+\-@]/.test(text)) text = `'${text}`;
      return `"${text.replaceAll('"', '""')}"`;
    };
    const rows = [['date', 'result', 'status', 'progress_percent', 'work_ref', 'why_important', 'next_step', 'focus_window_plan', 'evidence', 'created_at', 'updated_at', 'edits'], ...view().entries.map(item => [item.date, item.text, item.status, item.progress, item.workRef, item.whyImportant, item.nextStep, item.focusWindow, item.evidence, item.createdAt, item.updatedAt, item.revisions.length])];
    writeAtomic(join(dirname(file), 'daily-results.csv'), `\uFEFF${rows.map(row => row.map(cell).join(',')).join('\r\n')}\r\n`);
  }
  function save(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Укажи результат дня.');
    if (!validDate(input.date) || input.date > today()) throw new Error('Укажи прошедшую или сегодняшнюю дату.');
    if (typeof input.text !== 'string' || !input.text.trim() || input.text.length > 2000) throw new Error('Запиши результат: от 1 до 2000 символов.');
    if (!['planned', 'in_progress', 'blocked', 'ready'].includes(input.status)) throw new Error('Выбери состояние результата.');
    if (typeof input.evidence !== 'string' || input.evidence.length > 1000) throw new Error('Подтверждение: не больше 1000 символов.');
    if (input.status === 'ready' && !input.evidence.trim()) throw new Error('Укажи, какой результат получен и как проверена его готовность.');
    const previous = data.entries.find(item => item.date === input.date);
    if (input.expectedUpdatedAt !== (previous?.updatedAt ?? null)) throw new Error('Результат уже изменён. Обнови данные перед повторным сохранением.');
    const text = input.text.trim(), evidence = input.evidence.trim();
    const extra = {};
    for (const [key, label, max] of [['whyImportant', 'Почему важно', 1000], ['nextStep', 'Следующий ход', 1000], ['focusWindow', 'Окно фокуса', 160]]) {
      const value = input[key] ?? previous?.[key] ?? '';
      if (typeof value !== 'string' || value.length > max) throw new Error(`${label}: не больше ${max} символов.`);
      extra[key] = value.trim();
    }
    extra.workRef = input.workRef === undefined ? previous?.workRef ?? null : validateWorkRef(input.workRef);
    if (input.progress !== undefined && input.progress !== null && (!Number.isInteger(input.progress) || input.progress < 0 || input.progress > 100)) throw new Error('Прогресс: целое число от 0 до 100 или пустое поле.');
    extra.progress = input.status === 'ready' ? 100 : input.progress === undefined ? (previous?.status === 'ready' ? null : previous?.progress ?? null) : input.progress;
    if (extra.progress !== null && (!Number.isInteger(extra.progress) || extra.progress < 0 || extra.progress > 100)) throw new Error('Прогресс: целое число от 0 до 100 или пустое поле.');
    if (extra.progress === 100 && input.status !== 'ready') throw new Error('Для 100% выбери «Готово» и укажи подтверждение результата.');
    const previousView = view().entries.find(item => item.date === input.date);
    if (previous?.text === text && previous.status === input.status && previous.evidence === evidence && Object.entries(extra).every(([key,value]) => previousView[key] === value)) return structuredClone(previousView);
    const now = new Date(Math.max(Date.now(), previous ? Date.parse(previous.updatedAt) + 1 : 0)).toISOString();
    const entry = {
      ...previous, date: input.date, text, status: input.status, evidence, ...extra, createdAt: previous?.createdAt ?? now, updatedAt: now,
      revisions: previous ? [...previous.revisions, { text: previous.text, status: previous.status, evidence: previous.evidence, progress: previousView.progress, workRef: previousView.workRef, whyImportant: previousView.whyImportant, nextStep: previousView.nextStep, focusWindow: previousView.focusWindow, updatedAt: previous.updatedAt, replacedAt: now }] : []
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
