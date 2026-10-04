import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { replaceFile } from './atomic-file.mjs';
import { dirname, join } from 'node:path';
import { today, validDate } from './store.mjs';

export const indicatorDefinitions = [
  {
    id: 'rhythm', title: 'Распорядок дня', targetMin: 7, targetMax: 8,
    context: 'Оцени удобство своего режима сна, питания, работы и отдыха.',
    nextStep: 'Выбери одно изменение режима и проверь его при следующей оценке.'
  },
  {
    id: 'productivity', title: 'Продуктивность и стресс', targetMin: 7, targetMax: 8,
    context: 'Оцени нагрузку и удовлетворённость сделанным.',
    nextStep: 'Каждый день письменно отмечать, что сделано и какой появился результат.'
  },
  {
    id: 'results', title: 'Результативность', targetMin: 7, targetMax: 8,
    context: 'Оцени продвижение выбранных задач к рабочему результату.',
    nextStep: 'Выбери один основной результат дня и проверь его готовность.'
  },
  {
    id: 'development', title: 'Темп развития', targetMin: 7, targetMax: 8,
    context: 'Оцени регулярность обучения и применения изученного.',
    nextStep: 'Выдели время на чтение, размышление и применение; запиши результат.'
  }
];

export function createIndicatorStore(file) {
  mkdirSync(dirname(file), { recursive: true });
  const tableFile = join(dirname(file), 'indicator-ratings.csv');
  const csvCell = value => `"${String(value ?? '').replaceAll('"', '""')}"`;
  let data;
  if (existsSync(file)) {
    data = JSON.parse(readFileSync(file, 'utf8'));
    if (data.version !== 1 || !Array.isArray(data.observations)) throw new Error('Неподдерживаемый формат самооценки. Исходный файл сохранён.');
  } else {
    data = { version: 1, observations: [], updatedAt: new Date().toISOString() };
    writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
  }

  function syncTable() {
    const rows = [['date', 'indicator_id', 'indicator', 'score', 'target_min', 'target_max', 'note']];
    for (const item of [...data.observations].sort((a, b) => b.date.localeCompare(a.date))) {
      const definition = indicatorDefinitions.find(definition => definition.id === item.indicatorId);
      rows.push([item.date, item.indicatorId, definition?.title ?? item.indicatorId, item.score, definition?.targetMin ?? '', definition?.targetMax ?? '', item.note]);
    }
    writeFileSync(`${tableFile}.tmp`, `\uFEFF${rows.map(row => row.map(csvCell).join(',')).join('\r\n')}\r\n`, 'utf8');
    replaceFile(`${tableFile}.tmp`, tableFile);
  }
  syncTable();

  function save(next) {
    next.updatedAt = new Date().toISOString();
    writeFileSync(`${file}.tmp`, `${JSON.stringify(next, null, 2)}\n`, 'utf8');
    replaceFile(`${file}.tmp`, file);
    data = next;
    syncTable();
  }

  function getPeriod(start, end) {
    if (!validDate(start) || !validDate(end) || start > end) throw new Error('Некорректный период самооценки.');
    return {
      start, end, updatedAt: data.updatedAt,
      indicators: indicatorDefinitions.map(definition => {
        const observation = data.observations.filter(item => item.indicatorId === definition.id && item.date >= start && item.date <= end).sort((a, b) => b.date.localeCompare(a.date))[0];
        return { ...definition, score: observation?.score ?? null, assessedAt: observation?.date ?? null, note: observation?.note ?? null };
      })
    };
  }

  function rate(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Укажи оценку.');
    if (!indicatorDefinitions.some(item => item.id === input.indicatorId)) throw new Error('Неизвестный показатель.');
    if (!validDate(input.date) || input.date > today()) throw new Error('Укажи прошедшую или сегодняшнюю дату.');
    if (!Number.isInteger(input.score) || input.score < 0 || input.score > 10) throw new Error('Оценка должна быть целым числом от 0 до 10.');
    if (input.note !== undefined && (typeof input.note !== 'string' || input.note.length > 1000)) throw new Error('Заметка должна быть не длиннее 1000 символов.');
    const observation = { indicatorId: input.indicatorId, date: input.date, score: input.score, note: (input.note ?? '').trim() };
    const observations = data.observations.filter(item => item.indicatorId !== observation.indicatorId || item.date !== observation.date);
    save({ ...data, observations: [...observations, observation] });
    return observation;
  }

  function getAll() {
    return { indicators: indicatorDefinitions, observations: [...data.observations].sort((a, b) => b.date.localeCompare(a.date)) };
  }

  return { getPeriod, getAll, rate };
}
