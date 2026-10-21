import { pomodoroCapacitySummary } from '../public/pomodoro-capacity.js';
const dayMs = 86400000;
export function planDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('Укажи корректную дату плана.');
  const ms = Date.parse(`${value}T12:00:00Z`);
  if (!Number.isFinite(ms) || new Date(ms).toISOString().slice(0, 10) !== value) throw new Error('Укажи корректную дату плана.');
  return value;
}
export function planShift(date, days) { return new Date(Date.parse(`${planDate(date)}T12:00:00Z`) + days * dayMs).toISOString().slice(0, 10); }
export function planMonday(date) { const d = new Date(`${planDate(date)}T12:00:00Z`); return planShift(date, -((d.getUTCDay() + 6) % 7)); }

// Resolve rules for a day without rewriting earlier plans or their history.
export function pomodoroTargetsForDate(records, date) {
  const selected = new Map();
  for (const row of records ?? []) {
    if (row.date !== date && !(row.repeat === 'daily' && row.date <= date)) continue;
    const previous = selected.get(row.workRef);
    if (!previous || row.date > previous.date) selected.set(row.workRef, row);
  }
  return [...selected.values()].filter(row => row.target != null)
    .map(row => ({ ...structuredClone(row), sourceDate: row.date, date }));
}

export function pomodoroFacts(sessions) {
  const seen = new Set(), facts = [];
  for (const s of sessions ?? []) {
    if (!s.id || seen.has(s.id) || s.status !== 'finished' || s.phase !== 'work' || s.mode !== 'pomodoro'
        || s.completedPomodoros !== 1 || s.syncResolution === 'excluded' || !s.workRef) continue;
    const stamp = Date.parse(s.finishedAt);
    if (!Number.isFinite(stamp)) continue;
    seen.add(s.id);
    facts.push({ sessionId: s.id, workRef: s.workRef, date: new Date(stamp + 5 * 3600000).toISOString().slice(0, 10), count: 1 });
  }
  return facts;
}

export function pomodoroPlanView(data, date, selectedWeek = date) {
  planDate(date);
  const week = planMonday(selectedWeek), end = planShift(week, 6);
  const relevant = d => d === date || d === planShift(date, -1) || d >= week && d <= end;
  const days = [...new Set([date, planShift(date, -1), ...Array.from({ length: 7 }, (_, i) => planShift(week, i))])];
  const records = days.flatMap(d => pomodoroTargetsForDate(data.pomodoroTargets, d));
  const facts = pomodoroFacts(data.timer?.sessions).filter(f => relevant(f.date));
  const count = (ref, d) => facts.filter(f => f.workRef === ref && f.date === d).length;
  const targets = records.filter(t => t.target != null).map(t => ({ ...structuredClone(t), actualPomodoros: count(t.workRef, t.date) }));
  const todayTargets = targets.filter(t => t.date === date);
  const weekRows = targets.filter(t => t.date >= week && t.date <= end);
  const groups = new Map();
  for (const t of weekRows) {
    const key = `${t.workRef}\0${t.title}`;
    if (!groups.has(key)) groups.set(key, { workRef: t.workRef, title: t.title, days: [], target: 0, actualPomodoros: 0 });
    const row = groups.get(key);
    row.days.push({ date: t.date, target: t.target, actualPomodoros: t.actualPomodoros });
    row.target += t.target; row.actualPomodoros += t.actualPomodoros;
  }
  return { pomodoroTargets: structuredClone(data.pomodoroTargets ?? []), pomodoroFacts: facts,
    pomodoroCapacities: structuredClone(data.pomodoroCapacities ?? []),
    pomodoroPlan: { date, hasPlan: todayTargets.length > 0, targets: todayTargets,
      capacity: pomodoroCapacitySummary(todayTargets, data.pomodoroCapacities, date),
      target: todayTargets.reduce((n, t) => n + t.target, 0), actualPomodoros: todayTargets.reduce((n, t) => n + t.actualPomodoros, 0) },
    pomodoroWeek: { week, end, days: Array.from({ length: 7 }, (_, i) => planShift(week, i)), rows: [...groups.values()],
      capacities: Array.from({length:7}, (_, i) => { const day=planShift(week,i); return pomodoroCapacitySummary(targets.filter(t=>t.date===day),data.pomodoroCapacities,day); }) } };
}
