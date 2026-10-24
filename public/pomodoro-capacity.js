// Shared by the server and browser. A capacity is a personal planning warning,
// never a reason to discard time or block an active session.
export function pomodoroCapacityOn(rules, date) {
  return (rules ?? []).filter(r => r.date <= date)
    .reduce((latest, r) => !latest || r.date > latest.date ? r : latest, null)?.limit ?? null;
}

export function completedPomodorosOn(facts, date) {
  return new Set((facts ?? []).filter(f => f.date === date && f.sessionId)
    .map(f => f.sessionId)).size;
}

export function pomodoroCapacitySummary(targets, rules, date, candidate) {
  const effective = candidate
    ? [...targets.filter(t => t.workRef !== candidate.workRef), candidate]
    : targets;
  const planned = effective.reduce((sum, t) => sum + (t.target ?? 0), 0);
  const limit = pomodoroCapacityOn(rules, date);
  const over = limit != null && planned > limit;
  return { date, planned, limit, over,
    message: limit == null ? `План: ${planned} помидорок · дневной лимит не задан.`
      : over ? `В плане сейчас ${planned} помидорок, а твой лимит — ${limit} в день. Превышение: ${planned - limit}. Проверь план с учётом своих сил.`
      : `План: ${planned} помидорок · твой лимит: ${limit} в день.` };
}
