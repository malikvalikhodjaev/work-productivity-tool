import { posix } from 'node:path';
import { createStore } from './store.mjs';
import { createWorkspaceStore } from './workspace.mjs';
import { createIndicatorStore } from './indicators.mjs';
import { createDailyProblemStore } from './daily-problems.mjs';
import { createDailyResultStore } from './daily-results.mjs';
import { createReferenceStore } from './references.mjs';

export const snapshotFiles = ['dashboard.json', 'workspace.json', 'indicators.json', 'daily-problems.json', 'daily-results.json', 'references.json', 'imports/coda-snapshot.json', 'imports/alpha-reference.json'];
const requiredFiles = snapshotFiles.slice(0, 6);
const key = file => posix.normalize(String(file).replaceAll('\\', '/'));

// Every request owns its filesystem. Legacy read-time migrations/CSV generation
// remain temporary; neither the source files nor the durable snapshot changes.
export function memoryStorage(files) {
  const data = new Map(Object.entries(files).map(([name, value]) => [key(`/data/${name}`), value]));
  const readFileSync = (file, encoding) => {
    const value = data.get(key(file));
    if (value === undefined) { const error = new Error('Snapshot file unavailable.'); error.code = 'ENOENT'; throw error; }
    return encoding ? String(value) : new TextEncoder().encode(String(value));
  };
  return {
    existsSync: file => data.has(key(file)), mkdirSync() {}, readFileSync,
    writeFileSync: (file, value) => data.set(key(file), String(value)),
    copyFileSync: (source, target) => data.set(key(target), readFileSync(source, 'utf8')),
    replaceFile(source, target) { data.set(key(target), readFileSync(source, 'utf8')); data.delete(key(source)); }
  };
}

export function validateSnapshot(input) {
  if (!input || input.format !== 'indicators-work-snapshot' || input.version !== 1 || !Number.isFinite(Date.parse(input.capturedAt))) throw new Error('Неверный формат снимка.');
  if (!input.files || typeof input.files !== 'object' || Array.isArray(input.files)) throw new Error('Нужны исходные файлы снимка.');
  for (const name of requiredFiles) if (typeof input.files[name] !== 'string') throw new Error(`Отсутствует ${name}.`);
  for (const [name, raw] of Object.entries(input.files)) {
    if (!snapshotFiles.includes(name) || typeof raw !== 'string' || raw.length > 1000000) throw new Error('Недопустимый файл снимка.');
    const value = JSON.parse(raw);
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Исходный файл должен содержать объект.');
  }
  if (!Array.isArray(input.attachments) || input.attachments.length > 100) throw new Error('Неверный список вложений.');
  const attachments = new Set();
  for (const item of input.attachments) {
    if (!/^reference-assets\/[a-z0-9-]+\.png$/.test(item.path) || !/^[a-f0-9]{64}$/.test(item.sha256) || !Number.isInteger(item.size) || item.size < 1 || item.size > 5000000 || attachments.has(item.path)) throw new Error('Неверное вложение.');
    attachments.add(item.path);
  }
  // Validate all store schemas before publishing a snapshot.
  createSnapshotView(input);
  return input;
}

export function createSnapshotView(snapshot) {
  const storage = memoryStorage({ ...snapshot.files, ...Object.fromEntries(snapshot.attachments.map(item => [item.path, ''])) });
  let store;
  const workspace = createWorkspaceStore('/data/workspace.json', () => store.getPortfolio(), { storage });
  store = createStore('/data/dashboard.json', { storage, validateWorkRef: workspace.validateRef });
  const indicators = createIndicatorStore('/data/indicators.json', { storage });
  const problems = createDailyProblemStore('/data/daily-problems.json', { storage });
  const results = createDailyResultStore('/data/daily-results.json', { storage, validateWorkRef: workspace.validateRef });
  const references = createReferenceStore('/data/references.json', { storage });
  const optional = (name, empty) => snapshot.files[name] ? { ...JSON.parse(snapshot.files[name]), available: true } : { ...empty, available: false };
  return {
    attachment(id) {
      const file = references.attachment(id);
      return file ? snapshot.attachments.find(item => key(`/data/${item.path}`) === key(file)) ?? null : null;
    },
    get(url) {
      switch (url.pathname) {
        case '/api/references': return references.view();
        case '/api/daily-results': return results.view();
        case '/api/daily-problems': return problems.view();
        case '/api/workspace': return workspace.view();
        case '/api/portfolio': return store.getPortfolio();
        case '/api/time-entries': return store.getStoredEntries();
        case '/api/alphas/export': return store.alphaBackup();
        case '/api/alphas/history': return { entries: store.alphaHistory(url.searchParams.get('id')) };
        case '/api/indicator-ratings': return indicators.getAll();
        case '/api/dashboard': return store.getWeek(url.searchParams.get('week') ?? undefined);
        case '/api/overview': { const activity = store.getPeriod(url.searchParams.get('period') ?? '7d'); return { activity, assessment: indicators.getPeriod(activity.start, activity.end) }; }
        case '/api/finance': { const period = store.getPeriod(url.searchParams.get('period') ?? '7d'); return workspace.finance(period.start, period.end); }
        case '/api/today': {
          const date = url.searchParams.get('date');
          if (date && date > results.view().today) throw new Error('Выбери прошедшую или сегодняшнюю дату.');
          const day = store.getToday(date ?? undefined);
          return { ...day, result: results.view().entries.find(item => item.date === day.date) ?? null, problem: problems.view().entries.find(item => item.date === day.date) ?? null };
        }
        case '/api/imported-data': return {
          snapshot: optional('imports/coda-snapshot.json', { capturedAt: null, sources: {}, work: [], goals: [], issues: [] }),
          reference: optional('imports/alpha-reference.json', { capturedAt: null, sources: {}, rows: [], roles: [], mistakes: [], actions: [], guidance: [], objectFields: [] })
        };
        default: return undefined;
      }
    }
  };
}
