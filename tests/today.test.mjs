import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createStore } from '../lib/store.mjs';
import { createDailyResultStore } from '../lib/daily-results.mjs';

test('Сегодня считает текущую неделю до выбранного дня, исключая будущие записи и другие недели', () => {
  const dir = mkdtempSync(join(tmpdir(), 'rhythm-today-'));
  try {
    const store = createStore(join(dir, 'dashboard.json'));
    assert.equal(store.getToday('2026-09-30').dailyTime.total, null);
    assert.equal(store.getToday('2026-09-30').norms.find(item => item.id === 'reading').actual, null);
    store.updateTargets('2026-09-28', { alphas: 4 });
    store.addEntry({ metricId: 'reading', date: '2026-09-27', amount: 10 });
    store.addEntry({ metricId: 'reading', date: '2026-09-28', amount: 5 });
    store.addEntry({ metricId: 'reading', date: '2026-09-30', amount: 1 });
    store.addEntry({ metricId: 'mentor', date: '2026-09-30', amount: 4 });
    store.addEntry({ metricId: 'reading', date: '2026-10-01', amount: 8 });
    store.addEntry({ metricId: null, allocation: 'outside', date: '2026-09-30', amount: 2 });
    store.addEntry({ metricId: 'alphas', date: '2026-09-30', amount: 2 });
    const snapshot = store.getToday('2026-09-30');
    const reading = snapshot.norms.find(item => item.id === 'reading');
    assert.equal(snapshot.daysRemaining, 5);
    assert.equal(reading.actual, 6);
    assert.equal(reading.remaining, 4);
    assert.equal(reading.dailyPace, .8);
    assert.equal(snapshot.norms.find(item => item.id === 'mentor').remaining, 0);
    assert.equal(snapshot.norms.find(item => item.id === 'alphas').actual, 2);
    assert.equal(snapshot.remainingHours, 14);
    assert.equal(snapshot.dailyTime.total, 7);
    assert.equal(snapshot.weeklyTime.total, 12);
    assert.equal(snapshot.completed, 1);
    assert.equal(store.getToday('2026-10-04').daysRemaining, 1);
    assert.equal(store.getToday('2026-09-28').daysRemaining, 7);
    store.updateTargets('2026-09-28', { reading: null });
    assert.ok(!store.getToday('2026-09-30').norms.some(item => item.id === 'reading'));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('Результат дня сохраняется с подтверждением и правками; новый день не наследует готовность', () => {
  const dir = mkdtempSync(join(tmpdir(), 'rhythm-daily-results-'));
  try {
    const file = join(dir, 'daily-results.json');
    const store = createDailyResultStore(file);
    const date = '2026-09-30';
    assert.deepEqual(store.view().entries, []);
    const planned = store.save({ date, text: 'Первая версия в использовании', status: 'planned', evidence: '', expectedUpdatedAt: null });
    assert.throws(() => store.save({ date, text: planned.text, status: 'ready', evidence: '', expectedUpdatedAt: planned.updatedAt }), /готовность/);
    const ready = store.save({ date, text: planned.text, status: 'ready', evidence: 'Проверил в браузере и использовал для планирования.', expectedUpdatedAt: planned.updatedAt });
    assert.equal(ready.revisions[0].status, 'planned');
    assert.equal(ready.revisions[0].evidence, '');
    assert.throws(() => store.save({ date, text: 'Старая вкладка', status: 'planned', evidence: '', expectedUpdatedAt: planned.updatedAt }), /изменён/);
    assert.deepEqual(createDailyResultStore(file).view().entries, [ready]);
    assert.ok(!store.view().entries.some(item => item.date === '2026-10-01'));
    assert.ok(readFileSync(join(dir, 'daily-results.csv'), 'utf8').includes(ready.evidence));
    assert.throws(() => store.save({ date: '2999-01-01', text: 'Будущее', status: 'planned', evidence: '', expectedUpdatedAt: null }), /дату/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
