import { copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { randomUUID } from 'node:crypto';
import { changePortfolio, initialPortfolio, portfolioView } from './portfolio.mjs';

export const metrics = [
  { id: 'guides', title: 'Руководства и проект', unit: 'hours', target: 10, color: 'blue', description: 'Самостоятельная работа' },
  { id: 'mentor', title: 'Разбор с наставником', unit: 'hours', target: 3, color: 'blue', description: 'Работа с наставником' },
  { id: 'reading', title: 'Чтение', unit: 'hours', target: 10, color: 'purple', description: 'Отдельное время на чтение' },
  { id: 'house_sale', title: 'Продажа дома', unit: 'hours', target: null, color: 'orange', description: 'Объявления, показы, переговоры' },
  { id: 'business', title: 'Бизнес', unit: 'hours', target: null, color: 'teal', description: 'Работа над своими проектами' },
  { id: 'work_support', title: 'Поддержка рабочих задач', unit: 'hours', target: null, color: 'blue', description: 'Текущая работа и сопровождение' },
  { id: 'household', title: 'Домашние дела', unit: 'hours', target: null, color: 'pink', description: 'Дом и бытовые задачи' },
  { id: 'other', title: 'Остальные нужды', unit: 'hours', target: null, color: 'slate', description: 'Другие направления недели' },
  { id: 'alphas', title: 'Заполненные альфы', unit: 'count', target: null, color: 'teal', description: 'Заполненные слоты и ручные записи' }
];

export function validDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T12:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

export function today() {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Tashkent', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
}

export function monday(value) {
  if (!validDate(value)) throw new Error('Укажи корректную дату.');
  const date = new Date(`${value}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() - (date.getUTCDay() + 6) % 7);
  return date.toISOString().slice(0, 10);
}

export function shiftDate(value, days) {
  const date = new Date(`${value}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

const round = value => Math.round((value + Number.EPSILON) * 100) / 100;

export function createStore(file, { validateWorkRef = ref => { if (ref) throw new Error('Связи объектов недоступны.'); return null; } } = {}) {
  mkdirSync(dirname(file), { recursive: true });
  let data;
  if (existsSync(file)) {
    data = JSON.parse(readFileSync(file, 'utf8'));
    if (data.version !== 1 || !data.plans || !Array.isArray(data.entries)) throw new Error('Неподдерживаемый формат файла данных. Исходный файл сохранён.');
  } else {
    data = { version: 1, plans: {}, entries: [], updatedAt: new Date().toISOString() };
  }

  function save(next) {
    next.updatedAt = new Date().toISOString();
    writeFileSync(`${file}.tmp`, `${JSON.stringify(next, null, 2)}\n`, 'utf8');
    renameSync(`${file}.tmp`, file);
    data = next;
  }

  if (!data.portfolio) {
    if (existsSync(file) && !existsSync(`${file}.before-projects.json`)) copyFileSync(file, `${file}.before-projects.json`);
    save({ ...data, portfolio: initialPortfolio() });
  }
  if (data.portfolio.version !== 1 || !Array.isArray(data.portfolio.projects) || !Array.isArray(data.portfolio.alphas) || !Array.isArray(data.portfolio.tasks)) throw new Error('Неподдерживаемый формат проектов. Исходный файл сохранён.');

  function updatePortfolio(action, input) {
    const portfolio = changePortfolio(data.portfolio, action, input, validDate);
    save({ ...data, portfolio });
    return portfolioView(data.portfolio);
  }

  function ensureWeek(week) {
    if (data.plans[week]) return;
    const earlier = Object.keys(data.plans).filter(key => key < week).sort().at(-1);
    const targets = earlier ? { ...data.plans[earlier] } : Object.fromEntries(metrics.map(metric => [metric.id, metric.target]));
    save({ ...data, plans: { ...data.plans, [week]: targets } });
  }

  function getWeek(input = today()) {
    const week = monday(input);
    ensureWeek(week);
    const end = shiftDate(week, 6);
    const entries = data.entries.filter(entry => entry.date >= week && entry.date <= end).sort((a, b) => b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt));
    const items = metrics.map(metric => {
      const records = entries.filter(entry => entry.metricId === metric.id);
      const filledCards = metric.id === 'alphas' ? data.portfolio.alphas.filter(alpha => alpha.filledDate && alpha.filledDate >= week && alpha.filledDate <= end).length : 0;
      const actual = round(records.reduce((sum, entry) => sum + entry.amount, 0) + filledCards);
      const target = data.plans[week][metric.id] ?? null;
      return { ...metric, target, actual, filledCards, recordCount: records.length + filledCards, percent: target === null ? null : Math.round(actual / target * 100), remaining: target === null ? null : round(Math.max(0, target - actual)) };
    });
    const hours = items.filter(item => item.unit === 'hours');
    return {
      week, end, today: today(), currentWeek: monday(today()), timezone: 'Asia/Tashkent', updatedAt: data.updatedAt,
      metrics: items, entries, time: timeDetails(week, end),
      summary: { actualHours: round(entries.filter(e => e.metricId !== 'alphas').reduce((sum, e) => sum + e.amount, 0)), hourRecords: entries.filter(e => e.metricId !== 'alphas').length, targetHours: round(hours.reduce((sum, item) => sum + (item.target ?? 0), 0)), configured: items.filter(item => item.target !== null).length, completed: items.filter(item => item.target !== null && item.actual >= item.target).length, unconfigured: items.filter(item => item.target === null).length }
    };
  }

  function getPeriod(input = '7d') {
    const days = { today: 1, '7d': 7, '30d': 30, '90d': 90 }[input];
    if (!days) throw new Error('Неизвестный период обзора.');
    const end = today();
    const start = shiftDate(end, 1 - days);
    const entries = data.entries.filter(entry => entry.date >= start && entry.date <= end);
    const items = metrics.map(metric => {
      const records = entries.filter(entry => entry.metricId === metric.id);
      const filledCards = metric.id === 'alphas' ? data.portfolio.alphas.filter(alpha => alpha.filledDate && alpha.filledDate >= start && alpha.filledDate <= end).length : 0;
      return { id: metric.id, title: metric.title, unit: metric.unit, actual: round(records.reduce((sum, entry) => sum + entry.amount, 0) + filledCards), recordCount: records.length + filledCards };
    });
    return { period: input, start, end, entriesCount: entries.length, metrics: items, time: timeDetails(start, end) };
  }

  function timeDetails(start, end) {
    const allocationTitles = { norm: 'По заданным нормативам', unplanned: 'Направление без норматива', outside: 'Вне нормативов', unclassified: 'Не разобрано' };
    const entries = data.entries.filter(e => e.metricId !== 'alphas' && e.date >= start && e.date <= end).map(e => {
      const week = monday(e.date);
      const plan = data.plans[week] ?? {};
      const metric = metrics.find(m => m.id === e.metricId);
      const allocation = metric ? (plan[metric.id] > 0 ? 'norm' : 'unplanned') : (e.allocation ?? 'unclassified');
      return { ...e, workType: e.workType || 'Не разобрано', workRef: e.workRef ?? null, allocation, direction: metric?.title ?? allocationTitles[allocation] };
    });
    const total = round(entries.reduce((sum, e) => sum + e.amount, 0));
    const by = key => [...new Set(entries.map(e => e[key]))].map(value => ({ key: value, title: key === 'allocation' ? allocationTitles[value] : value, hours: round(entries.filter(e => e[key] === value).reduce((sum, e) => sum + e.amount, 0)) })).sort((a,b) => b.hours - a.hours);
    return { total: entries.length ? total : null, records: entries.length, byAllocation: by('allocation'), byWorkType: by('workType'), entries };
  }

  function entryMeta(input) {
    const metric = metrics.find(m => m.id === input.metricId);
    if (!metric && input.metricId !== null) throw new Error('Выбери направление или время вне нормативов.');
    const allocation = metric ? 'assigned' : input.allocation;
    if (!metric && !['outside', 'unclassified'].includes(allocation)) throw new Error('Укажи: вне нормативов или не разобрано.');
    const workType = input.workType ?? '';
    if (typeof workType !== 'string' || workType.length > 80) throw new Error('Характер работы: не больше 80 символов.');
    return { metric, allocation, workType: workType.trim() || null, workRef: validateWorkRef(input.workRef) };
  }

  function updateTargets(input, changes) {
    const week = monday(input);
    if (!changes || typeof changes !== 'object' || Array.isArray(changes) || Object.keys(changes).length === 0) throw new Error('Укажи нормативы для сохранения.');
    for (const [id, value] of Object.entries(changes)) {
      const metric = metrics.find(item => item.id === id);
      if (!metric) throw new Error('Неизвестное направление.');
      if (value !== null && (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value > (metric.unit === 'hours' ? 168 : 10000) || (metric.unit === 'count' && !Number.isInteger(value)))) throw new Error(metric.unit === 'hours' ? 'Норматив часов должен быть больше 0 и не больше 168.' : 'Норматив альф должен быть целым числом от 1 до 10 000.');
    }
    ensureWeek(week);
    save({ ...data, plans: { ...data.plans, [week]: { ...data.plans[week], ...changes } } });
    return getWeek(week);
  }

  function addEntry(input) {
    const meta = entryMeta(input);
    const metric = meta.metric ?? { id: null, unit: 'hours' };
    if (!validDate(input.date)) throw new Error('Укажи корректную дату записи.');
    if (typeof input.amount !== 'number' || !Number.isFinite(input.amount) || input.amount <= 0 || input.amount > (metric.unit === 'hours' ? 24 : 10000) || (metric.unit === 'count' && !Number.isInteger(input.amount))) throw new Error(metric.unit === 'hours' ? 'Укажи время больше 0 и не больше 24 часов.' : 'Укажи целое количество альф от 1 до 10 000.');
    if (input.title !== undefined && (typeof input.title !== 'string' || input.title.length > 300)) throw new Error('Описание должно быть не длиннее 300 символов.');
    const source = input.source ?? 'manual';
    if (typeof source !== 'string' || !/^[a-z0-9_-]{1,40}$/.test(source)) throw new Error('Некорректный источник записи.');
    if (input.externalId !== undefined && (typeof input.externalId !== 'string' || input.externalId.length === 0 || input.externalId.length > 200)) throw new Error('Некорректный идентификатор внешней записи.');
    if (input.externalId) {
      const existing = data.entries.find(entry => entry.source === source && entry.externalId === input.externalId);
      if (existing) return { entry: existing, duplicate: true };
    }
    const entry = { id: randomUUID(), metricId: metric.id, allocation: meta.allocation, workType: meta.workType, workRef: meta.workRef, date: input.date, amount: round(input.amount), title: (input.title ?? '').trim(), source, createdAt: new Date().toISOString() };
    if (entry.amount <= 0) throw new Error('Минимальное значение записи — 0,01.');
    if (input.externalId) entry.externalId = input.externalId;
    ensureWeek(monday(entry.date));
    save({ ...data, entries: [...data.entries, entry] });
    return { entry, duplicate: false };
  }

  function removeEntry(id) {
    const entry = data.entries.find(item => item.id === id);
    if (!entry) throw new Error('Запись уже удалена или не найдена.');
    save({ ...data, entries: data.entries.filter(item => item.id !== id) });
    return entry;
  }

  function classifyEntry(id, input) {
    const existing = data.entries.find(e => e.id === id);
    if (!existing) throw new Error('Запись не найдена.');
    const meta = entryMeta(input);
    if ((existing.metricId === 'alphas') !== (meta.metric?.id === 'alphas')) throw new Error('Нельзя превращать часы в количество альф и обратно.');
    const entry = { ...existing, metricId: meta.metric?.id ?? null, allocation: meta.allocation, workType: meta.workType, workRef: meta.workRef, classificationHistory: [...(existing.classificationHistory ?? []), { metricId: existing.metricId, allocation: existing.allocation ?? null, workType: existing.workType ?? null, workRef: existing.workRef ?? null, changedAt: new Date().toISOString() }] };
    save({ ...data, entries: data.entries.map(e => e.id === id ? entry : e) });
    return entry;
  }

  ensureWeek(monday(today()));
  return { getWeek, getPeriod, updateTargets, addEntry, classifyEntry, removeEntry, getPortfolio: () => portfolioView(data.portfolio), updatePortfolio };
}
