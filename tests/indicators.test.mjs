import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createIndicatorStore } from '../lib/indicators.mjs';
import { createStore, today } from '../lib/store.mjs';

test('самооценки изначально пусты; сохранённая оценка не переносится на другой период', () => {
  const dir = mkdtempSync(join(tmpdir(), 'rhythm-indicators-'));
  try {
    const file = join(dir, 'indicators.json');
    const store = createIndicatorStore(file);
    const baseline = store.getPeriod('2026-09-28', '2026-09-28');
    assert.deepEqual(baseline.indicators.map(item => item.score), [null, null, null, null]);
    assert.equal(store.getPeriod('2026-09-29', '2026-09-29').indicators[0].score, null);
    const date = today();
    store.rate({ indicatorId: 'rhythm', date, score: 6, note: 'Первая оценка.' });
    store.rate({ indicatorId: 'rhythm', date, score: 7, note: 'Лёг раньше и завершил работу до ночи.' });
    assert.equal(store.getAll().observations.length, 1);
    assert.equal(store.getPeriod('2000-01-01', '2000-01-01').indicators[0].score, null);
    assert.equal(createIndicatorStore(file).getPeriod(date, date).indicators[0].score, 7);
    const table = readFileSync(join(dir, 'indicator-ratings.csv'), 'utf8');
    assert.match(table, /"date","indicator_id","indicator","score"/);
    assert.ok(table.includes(`"${date}","rhythm","Распорядок дня","7"`));
    assert.throws(() => store.rate({ indicatorId: 'rhythm', date, score: 11 }), /от 0 до 10/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('быстрый период считает только фактические записи и не подменяет отсутствие данных нулём', () => {
  const dir = mkdtempSync(join(tmpdir(), 'rhythm-period-'));
  try {
    const store = createStore(join(dir, 'dashboard.json'));
    const empty = store.getPeriod('7d');
    assert.equal(empty.metrics.find(item => item.id === 'house_sale').recordCount, 0);
    store.addEntry({ metricId: 'house_sale', date: today(), amount: 1.5, title: 'Работа по продаже дома' });
    const period = store.getPeriod('today');
    assert.equal(period.metrics.find(item => item.id === 'house_sale').actual, 1.5);
    assert.equal(period.metrics.find(item => item.id === 'business').recordCount, 0);
    assert.throws(() => store.getPeriod('invalid'), /Неизвестный период/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
