const textFields = ['description', 'criteria', 'evidence', 'nextStep'];
const lines = value => String(value ?? '').split(/\r?\n/).filter(s => s.trim()).length;
export function modelActivity(backup, week) {
  const aggregate = history => {
    const previous = new Map();
    let created = 0, edits = 0, renames = 0, filled = 0, addedLines = 0;
    for (const entry of history) {
      const before = previous.get(entry.alphaId), after = entry.snapshot;
      const inPeriod = !week || new Date(Date.parse(entry.at) + 5 * 3600000).toISOString().slice(0, 10) >= week && new Date(Date.parse(entry.at) + 5 * 3600000).toISOString().slice(0, 10) < new Date(Date.parse(week) + 7 * 86400000).toISOString().slice(0, 10);
      if (inPeriod && ['create', 'edit'].includes(entry.action)) {
        if (entry.action === 'create') created++;
        else edits++;
        if (before && ['uniqueName', 'typeName'].some(k => before[k] !== after[k])) renames++;
        for (const field of textFields) {
          if (!String(before?.[field] ?? '').trim() && String(after[field] ?? '').trim()) filled++;
          addedLines += Math.max(0, lines(after[field]) - lines(before?.[field]));
        }
      }
      previous.set(entry.alphaId, after);
    }
    return { created, edits, renames, filled, addedLines };
  };
  const history = [...(backup.history ?? [])].sort((a, b) => Date.parse(a.at) - Date.parse(b.at));
  return {
    week,
    recordedHistory: history.length > 0,
    activity: aggregate(history),
    rows: backup.alphas.length,
    adapted: backup.alphas.filter(a => a.uniqueName?.trim() && a.uniqueName.trim() !== a.typeName?.trim()).length,
    currentLines: backup.alphas.reduce((sum, a) => sum + textFields.reduce((n, k) => n + lines(a[k]), 0), 0),
    byProject: backup.projects.map(p => ({ projectId: p.id, ...modelActivityProject(p.id, backup, history, aggregate) })),
  };
}
function modelActivityProject(id, backup, history, aggregate) {
  const alphas = backup.alphas.filter(a => a.projectId === id), ids = new Set(alphas.map(a => a.id));
  return { rows: alphas.length, adapted: alphas.filter(a => a.uniqueName?.trim() && a.uniqueName.trim() !== a.typeName?.trim()).length, currentLines: alphas.reduce((sum, a) => sum + textFields.reduce((n, k) => n + lines(a[k]), 0), 0), activity: aggregate(history.filter(h => ids.has(h.alphaId))) };
}
