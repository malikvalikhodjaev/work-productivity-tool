import { randomUUID } from 'node:crypto';

export const defaultTimerSettings = Object.freeze({ workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, longBreakEvery: 4 });
const fail = message => { throw new Error(message); };
const conflict = message => { const error = new Error(message); error.status = 409; throw error; };
const minutes = (value, name) => {
  if (!Number.isInteger(value) || value < 1 || value > 240) fail(`${name}: целое число от 1 до 240 минут.`);
  return value;
};
export function timerSettings(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) fail('Укажи настройки таймера.');
  const result = {
    workMinutes: minutes(input.workMinutes, 'Рабочий интервал'),
    shortBreakMinutes: minutes(input.shortBreakMinutes, 'Короткий перерыв'),
    longBreakMinutes: minutes(input.longBreakMinutes, 'Длинный перерыв'),
    longBreakEvery: input.longBreakEvery
  };
  if (!Number.isInteger(result.longBreakEvery) || result.longBreakEvery < 1 || result.longBreakEvery > 20) fail('Цикл: от 1 до 20 помидорок.');
  return result;
}
export function timerState(value) {
  if (value === undefined) return { version: 1, revision: 0, settings: { ...defaultTimerSettings }, sessions: [], activeId: null, requests: [], workPlans: {}, cycleCount: 0 };
  if (!value || value.version !== 1 || !Number.isInteger(value.revision) || value.revision < 0 || !Array.isArray(value.sessions) || !Array.isArray(value.requests) || !value.workPlans || Array.isArray(value.workPlans) || typeof value.workPlans !== 'object' || !Number.isInteger(value.cycleCount) || value.cycleCount < 0) fail('Неподдерживаемое хранилище таймера. Исходник сохранён.');
  timerSettings(value.settings);
  const active = value.sessions.filter(s => ['running', 'paused'].includes(s.status));
  if (active.length > 1 || (active[0]?.id ?? null) !== value.activeId) fail('Некорректный активный сеанс таймера. Исходник сохранён.');
  for (const s of value.sessions) {
    if (!s.id || !['work','short_break','long_break'].includes(s.phase) || !['pomodoro','stopwatch'].includes(s.mode) || !['running','paused','finished','cancelled'].includes(s.status) || !Array.isArray(s.intervals) || s.intervals.some(i => !Number.isFinite(i.start) || !Number.isFinite(i.end) || i.end < i.start) || !Number.isFinite(Date.parse(s.startedAt)) || (s.status === 'running' && !Number.isFinite(s.runningSince))) fail('Некорректный сеанс таймера. Исходник сохранён.');
    timerSettings(s.settings);
    if ((s.mode === 'pomodoro' && (!Number.isInteger(s.plannedMs) || s.plannedMs < 60000 || s.plannedMs > 14400000)) || !Number.isInteger(s.completedPomodoros) || s.completedPomodoros < 0 || !Array.isArray(s.events)) fail('Некорректный план сеанса. Исходник сохранён.');
  }
  if (new Set(value.sessions.map(s => s.id)).size !== value.sessions.length) fail('Повторяющийся сеанс таймера. Исходник сохранён.');
  return structuredClone(value);
}
const savedMs = s => s.intervals.reduce((sum, i) => sum + i.end - i.start, 0);
export function sessionView(s, now) {
  const past = savedMs(s);
  const pending = s.status === 'running' ? Math.max(0, now - s.runningSince) : 0;
  const elapsedMs = past + (s.mode === 'pomodoro' ? Math.min(pending, Math.max(0, s.plannedMs - past)) : pending);
  const remainingMs = s.mode === 'pomodoro' ? Math.max(0, s.plannedMs - elapsedMs) : null;
  return { ...s, elapsedMs, remainingMs, expired: s.status === 'running' && remainingMs === 0,
    needsConfirmation: s.status === 'running' && (s.mode === 'pomodoro' ? now - (s.runningSince + Math.max(0, s.plannedMs - past)) > 300000 : elapsedMs > 8 * 3600000) };
}
function closeInterval(s, now) {
  if (s.status !== 'running') return;
  const amount = sessionView(s, now).elapsedMs - savedMs(s);
  if (amount > 0) s.intervals.push({ start: s.runningSince, end: s.runningSince + amount });
  s.runningSince = null;
}
function trimIntervals(intervals, durationMs) {
  const result = [];
  let left = durationMs;
  for (const i of intervals) {
    const amount = Math.min(left, i.end - i.start);
    if (amount > 0) result.push({ start: i.start, end: i.start + amount });
    left -= amount;
  }
  return result;
}
const atDate = ms => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Tashkent', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(ms));
function allocateDays(intervals) {
  const byDate = new Map();
  for (const i of intervals) {
    let cursor = i.start;
    while (cursor < i.end) {
      const date = atDate(cursor);
      const midnight = Date.parse(date + 'T00:00:00+05:00') + 86400000;
      const end = Math.min(i.end, midnight);
      byDate.set(date, (byDate.get(date) ?? 0) + end - cursor);
      cursor = end;
    }
  }
  return byDate;
}

export function changeTimer(value, action, input, { now = Date.now(), validateWorkRef, metrics, validDate, monday }) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) fail('Укажи действие таймера.');
  if (typeof input.requestId !== 'string' || !/^[a-zA-Z0-9_-]{8,100}$/.test(input.requestId)) fail('Нужен уникальный идентификатор запроса.');
  const timer = timerState(value);
  const signature = JSON.stringify({ action, input: Object.fromEntries(Object.entries(input).filter(([key]) => !['requestId','expectedRevision'].includes(key))) });
  const previous = timer.requests.find(r => r.id === input.requestId);
  if (previous) {
    if (previous.signature !== signature) conflict('Этот запрос уже использован для другого действия.');
    return { timer, entries: [], duplicate: true };
  }
  if (input.expectedRevision !== timer.revision) conflict('Таймер изменён на другом устройстве. Обнови состояние и повтори действие.');
  const stamp = new Date(now).toISOString();
  const entries = [];
  const active = timer.sessions.find(s => s.id === timer.activeId);
  if (action === 'settings') {
    timer.settings = timerSettings(input.settings);
  } else if (action === 'workTarget') {
    const ref = validateWorkRef(input.workRef);
    if (!ref) fail('Выбери конкретную работу для норматива.');
    if (!validDate(input.week)) fail('Укажи неделю норматива.');
    const hours = input.hours;
    if (hours !== null && (typeof hours !== 'number' || !Number.isFinite(hours) || hours <= 0 || hours > 168)) fail('Норматив работы: больше 0 и не больше 168 часов, либо пустое поле.');
    const week = monday(input.week);
    timer.workPlans[week] = { ...(timer.workPlans[week] ?? {}), [ref]: hours };
  } else if (action === 'start' || action === 'startBreak') {
    if (active) conflict('Уже есть активный сеанс. Сначала заверши его или отмени.');
    const settings = timerSettings(input.settings ?? timer.settings);
    const phase = action === 'start' ? 'work' : timer.cycleCount >= settings.longBreakEvery ? 'long_break' : 'short_break';
    const mode = phase === 'work' ? input.mode : 'pomodoro';
    if (!['pomodoro','stopwatch'].includes(mode)) fail('Выбери «Помидорка» или «Секундомер».');
    const title = phase === 'work' ? input.title : phase === 'long_break' ? 'Длинный перерыв' : 'Короткий перерыв';
    if (typeof title !== 'string' || !title.trim() || title.length > 300) fail('Название работы: от 1 до 300 символов.');
    const workRef = phase === 'work' ? validateWorkRef(input.workRef) : null;
    const metric = phase === 'work' && input.metricId !== null ? metrics.find(m => m.id === input.metricId && m.unit === 'hours') : null;
    if (phase === 'work' && input.metricId !== null && !metric) fail('Выбери часовой норматив или отдельное время.');
    const allocation = metric ? 'assigned' : phase === 'work' ? input.allocation : 'break';
    if (phase === 'work' && !metric && !['outside','unclassified'].includes(allocation)) fail('Укажи: вне нормативов или требует разбора.');
    const workType = input.workType ?? '';
    if (typeof workType !== 'string' || workType.length > 80) fail('Характер работы: до 80 символов.');
    const duration = phase === 'work' ? settings.workMinutes : phase === 'long_break' ? settings.longBreakMinutes : settings.shortBreakMinutes;
    const s = { id: randomUUID(), phase, mode, status: 'running', title: title.trim(), workRef, metricId: metric?.id ?? null, allocation,
      workType: workType.trim() || null, settings, plannedMs: mode === 'pomodoro' ? duration * 60000 : null,
      startedAt: stamp, updatedAt: stamp, runningSince: now, intervals: [], completedPomodoros: 0, events: [{ action, at: stamp }] };
    timer.sessions.push(s); timer.activeId = s.id;
  } else if (['pause','resume','extend','finish','cancel'].includes(action)) {
    if (!active || active.id !== input.sessionId) conflict('Активный сеанс уже изменён или завершён.');
    if (action === 'pause') {
      if (active.status !== 'running') conflict('Сеанс уже на паузе.');
      closeInterval(active, now); active.status = 'paused';
    } else if (action === 'resume') {
      if (active.status !== 'paused') conflict('Сеанс уже запущен.');
      if (active.mode === 'pomodoro' && savedMs(active) >= active.plannedMs) fail('Интервал истёк. Продли план или заверши сеанс.');
      active.status = 'running'; active.runningSince = now;
    } else if (action === 'extend') {
      if (active.mode !== 'pomodoro') fail('Секундомер не имеет ограниченного плана.');
      closeInterval(active, now);
      if (active.plannedMs + 300000 > 14400000) fail('Максимальный план — 240 минут.');
      active.plannedMs += 300000;
      if (active.status === 'running') active.runningSince = now;
    } else {
      closeInterval(active, now);
      if (input.workedSeconds !== undefined) {
        if (!Number.isInteger(input.workedSeconds) || input.workedSeconds < 0 || input.workedSeconds * 1000 > savedMs(active) || input.workedSeconds > 86400) fail('Уточнённый факт должен быть от 0 до учтённой длительности, не более 24 часов.');
        active.intervals = trimIntervals(active.intervals, input.workedSeconds * 1000);
      }
      if (action === 'finish' && savedMs(active) > 24 * 3600000) fail('Длинный сеанс требует уточнения: укажи факт не больше 24 часов.');
      active.status = action === 'finish' ? 'finished' : 'cancelled'; active.finishedAt = stamp;
      active.completedPomodoros = action === 'finish' && active.phase === 'work' && active.mode === 'pomodoro' && savedMs(active) >= active.plannedMs ? 1 : 0;
      if (active.completedPomodoros) timer.cycleCount++;
      if (action === 'finish' && active.phase === 'long_break') timer.cycleCount = 0;
      if (action === 'finish' && active.phase === 'work') {
        for (const [date, durationMs] of allocateDays(active.intervals)) entries.push({ id: randomUUID(), date, amount: durationMs / 3600000,
          durationSeconds: durationMs / 1000, metricId: active.metricId, allocation: active.allocation, workType: active.workType, workRef: active.workRef,
          title: active.title, source: 'dashboard_timer', externalId: active.id + ':' + date, timerSessionId: active.id, createdAt: stamp });
      }
      active.entryIds = entries.map(e => e.id); timer.activeId = null;
    }
    active.updatedAt = stamp; active.events.push({ action, at: stamp, ...(input.workedSeconds === undefined ? {} : { workedSeconds: input.workedSeconds }) });
  } else fail('Неизвестное действие таймера.');
  timer.revision++;
  timer.requests.push({ id: input.requestId, signature });
  timer.requests = timer.requests.slice(-256);
  return { timer, entries, duplicate: false };
}

export function timerView(value, { now = Date.now(), entries, week, end, entities = [] }) {
  const timer = timerState(value);
  const active = timer.sessions.find(s => s.id === timer.activeId);
  const sessions = timer.sessions.filter(s => s.finishedAt && atDate(Date.parse(s.finishedAt)) >= week && atDate(Date.parse(s.finishedAt)) <= end).map(s => sessionView(s, now)).reverse();
  const workEntries = entries.filter(e => e.source === 'dashboard_timer' && e.date >= week && e.date <= end);
  const seconds = e => e.durationSeconds ?? e.amount * 3600;
  const byWork = [...new Set(workEntries.map(e => e.workRef ?? 'activity:' + e.title))].map(key => {
    const records = workEntries.filter(e => (e.workRef ?? 'activity:' + e.title) === key);
    return { workRef: records[0].workRef, title: entities.find(e => e.ref === key)?.title ?? records[0].title, seconds: records.reduce((sum,e) => sum + seconds(e), 0), records: records.length };
  }).sort((a,b) => b.seconds - a.seconds);
  const plans = Object.entries(timer.workPlans[week] ?? {}).filter(([,hours]) => hours !== null).map(([ref,target]) => {
    const records = entries.filter(e => e.metricId !== 'alphas' && e.workRef === ref && e.date >= week && e.date <= end);
    const actual = records.length ? records.reduce((sum,e) => sum + e.amount, 0) : null;
    return { workRef: ref, title: entities.find(e => e.ref === ref)?.title ?? ref, target, actual, percent: actual === null ? null : Math.round(actual / target * 100) };
  });
  return { version: 1, revision: timer.revision, serverNow: new Date(now).toISOString(), settings: timer.settings, active: active ? sessionView(active, now) : null,
    cycleCount: timer.cycleCount, sessions, week, end, plans, byWork,
    summary: { workSeconds: workEntries.length ? workEntries.reduce((sum,e) => sum + seconds(e),0) : null,
      pomodoros: sessions.filter(s => s.phase === 'work').reduce((sum,s) => sum + s.completedPomodoros,0),
      breakSeconds: sessions.filter(s => s.phase !== 'work' && s.status === 'finished').reduce((sum,s) => sum + s.elapsedMs / 1000,0), records: workEntries.length } };
}
