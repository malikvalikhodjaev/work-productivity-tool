import { createHash, randomUUID } from 'node:crypto';
import { timerSettings, timerState, sessionView, allocateDays } from './timer.mjs';

const uuid = value => typeof value === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(value);
const fail = message => { throw new Error(message); };
const conflict = (message, kind, details = []) => { const e = new Error(message); e.status = 409; e.kind = kind; e.details = details; throw e; };
const canonical = value => JSON.stringify(value && typeof value === 'object' ? Array.isArray(value) ? value.map(v => JSON.parse(canonical(v))) : Object.fromEntries(Object.keys(value).sort().map(k => [k, JSON.parse(canonical(value[k]))])) : value);
export function connectOffline(data, deviceId, now) {
  if (!uuid(deviceId)) fail('Неверный идентификатор устройства.');
  const sync = structuredClone(data.offlineSync ?? { version: 1, serverId: randomUUID(), devices: {}, receipts: {} });
  if (!sync.devices[deviceId]) sync.devices[deviceId] = { createdAt: new Date(now).toISOString() };
  return sync;
}

export function importOffline(data, input, { now, metrics, validateWorkRef }) {
  const sync = data.offlineSync;
  if (!sync || input.serverId !== sync.serverId) conflict('Это другой сервер. Сохрани локальную выгрузку и подключи нужный сервер.', 'offline_server');
  if (!uuid(input.deviceId) || !sync.devices[input.deviceId]) fail('Сначала подключи это устройство.');
  const raw = input.session;
  if (!raw || !uuid(raw.id) || !['finished','cancelled'].includes(raw.status)) fail('Отправлять можно только завершённые или отменённые сеансы.');
  const hash = createHash('sha256').update(canonical(raw)).digest('hex');
  const key = input.deviceId + ':' + raw.id;
  const receipt = sync.receipts[key];
  if (receipt) {
    if (receipt.hash !== hash) conflict('Этот сеанс уже отправлен с другими данными. Исходник оставлен на устройстве.', 'offline_changed');
    return { duplicate: true, receipt, next: data };
  }
  if (input.resolution !== undefined && input.resolution !== 'exclude') fail('Неверное решение по записи.');
  const excluded = input.resolution === 'exclude';
  const started = Date.parse(raw.startedAt), finished = Date.parse(raw.finishedAt);
  const earliest = Date.parse('2010-01-01T00:00:00Z');
  if (!Number.isFinite(started) || !Number.isFinite(finished) || started < earliest || finished < started || finished > now + 300000) fail('Проверь дату и часы устройства. Сеанс сохранён локально.');
  if (!Array.isArray(raw.intervals) || raw.intervals.length > 1000) fail('Некорректные интервалы сеанса.');
  let previous = started, duration = 0;
  for (const i of raw.intervals) {
    if (!Number.isSafeInteger(i.start) || !Number.isSafeInteger(i.end) || i.start < previous || i.end < i.start || i.end > finished) fail('Интервалы должны идти по порядку и находиться внутри сеанса.');
    duration += i.end - i.start; previous = i.end;
  }
  if (duration > 86400000 && raw.status === 'finished' && !excluded) fail('Сеанс длиннее 24 часов требует уточнения на устройстве.');
  if (!['work','short_break','long_break'].includes(raw.phase) || !['pomodoro','stopwatch'].includes(raw.mode) || (raw.phase !== 'work' && raw.mode !== 'pomodoro')) fail('Некорректный режим сеанса.');
  const settings = timerSettings(raw.settings);
  if (raw.mode === 'pomodoro' && (!Number.isInteger(raw.plannedMs) || raw.plannedMs < 60000 || raw.plannedMs > 14400000 || duration > raw.plannedMs)) fail('Некорректный план помидорки.');
  if (raw.mode === 'stopwatch' && raw.plannedMs !== null) fail('У секундомера нет плана.');
  if (typeof raw.title !== 'string' || !raw.title.trim() || raw.title.length > 300 || (raw.workType !== null && (typeof raw.workType !== 'string' || raw.workType.length > 80))) fail('Некорректное описание работы.');
  if (!Array.isArray(raw.events) || raw.events.length > 512 || raw.events.some(e => typeof e.action !== 'string' || !Number.isFinite(Date.parse(e.at)))) fail('Некорректная история сеанса.');
  const metric = metrics.find(m => m.id === raw.metricId && m.unit === 'hours');
  if (!excluded && raw.phase === 'work' && raw.metricId !== null && !metric) conflict('Норматив больше недоступен. Запись осталась локально.', 'offline_reference');
  if (raw.phase === 'work' && (raw.metricId === null ? !['outside','unclassified'].includes(raw.allocation) : raw.allocation !== 'assigned')) fail('Некорректное назначение времени.');
  if (raw.phase !== 'work' && (raw.metricId !== null || raw.workRef !== null || raw.allocation !== 'break')) fail('Перерыв не может выполнять норматив.');
  const timer = timerState(data.timer);
  if (timer.sessions.some(s => s.id === raw.id)) conflict('Идентификатор сеанса уже занят.', 'offline_changed');
  let workRef = raw.workRef;
  if (!excluded) { try { workRef = validateWorkRef(raw.workRef); } catch { conflict('Связанная работа больше недоступна. Запись осталась локально.', 'offline_reference'); } }
  const intersections = [];
  if (!excluded && raw.status === 'finished' && raw.phase === 'work' && duration) {
    for (const s of timer.sessions.filter(s => s.phase === 'work' && s.status !== 'cancelled')) {
      const intervals = [...s.intervals];
      if (s.status === 'running') {
        const pending = sessionView(s, now).elapsedMs - s.intervals.reduce((v,i) => v + i.end - i.start, 0);
        if (pending > 0) intervals.push({ start: s.runningSince, end: s.runningSince + pending });
      }
      if (raw.intervals.some(a => intervals.some(b => a.start < b.end && b.start < a.end))) intersections.push({ id: s.id, title: s.title, status: s.status });
    }
    if (intersections.length) conflict('Рабочие интервалы пересекаются с таймером на сервере. Разбери запись перед учётом.', 'offline_overlap', intersections);
  }
  const stamp = new Date(now).toISOString();
  const s = { id: raw.id, phase: raw.phase, mode: raw.mode, status: excluded ? 'cancelled' : raw.status, title: raw.title.trim(), workRef,
    metricId: raw.metricId, allocation: raw.allocation, workType: raw.workType, settings, plannedMs: raw.plannedMs,
    startedAt: raw.startedAt, finishedAt: raw.finishedAt, updatedAt: stamp, runningSince: null, intervals: structuredClone(raw.intervals),
    completedPomodoros: !excluded && raw.status === 'finished' && raw.phase === 'work' && raw.mode === 'pomodoro' && duration >= raw.plannedMs ? 1 : 0,
    events: structuredClone(raw.events), offlineDeviceId: input.deviceId, offlineOriginal: structuredClone(raw), syncResolution: excluded ? 'excluded' : 'accepted', syncedAt: stamp };
  const entries = [];
  if (!excluded && s.status === 'finished' && s.phase === 'work') for (const [date, ms] of allocateDays(s.intervals)) entries.push({ id: randomUUID(), date, amount: ms / 3600000, durationSeconds: ms / 1000,
    metricId: s.metricId, allocation: s.allocation, workType: s.workType, workRef: s.workRef, title: s.title, source: 'dashboard_timer_offline',
    externalId: key + ':' + date, timerSessionId: s.id, offlineDeviceId: input.deviceId, createdAt: stamp });
  s.entryIds = entries.map(e => e.id); timer.sessions.push(s); timer.revision++;
  const nextSync = structuredClone(sync);
  const saved = { hash, status: excluded ? 'excluded' : 'accepted', sessionId: s.id, entryIds: s.entryIds, at: stamp };
  nextSync.receipts[key] = saved;
  return { duplicate: false, receipt: saved, next: { ...data, timer, offlineSync: nextSync, entries: [...data.entries, ...entries] } };
}
