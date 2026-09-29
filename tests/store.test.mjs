import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createStore, monday, validDate } from '../lib/store.mjs';

function fixture() {
  const file = path.join(mkdtempSync(path.join(tmpdir(), 'rhythm-test-')), 'dashboard.json');
  return { store: createStore(file), file };
}

test('Недельные границы: воскресенье относится к предыдущему понедельнику', () => {
  assert.equal(monday('2026-09-27'), '2026-09-21');
  assert.equal(monday('2026-09-28'), '2026-09-28');
  assert.equal(validDate('2026-02-30'), false);
});

test('Часы и альфы считаются раздельно; соседняя неделя не входит в прогресс', () => {
  const { store } = fixture();
  store.updateTargets('2026-09-28', { alphas: 4 });
  store.addEntry({ metricId: 'reading', date: '2026-09-28', amount: 2.5 });
  store.addEntry({ metricId: 'reading', date: '2026-10-04', amount: 0.5 });
  store.addEntry({ metricId: 'reading', date: '2026-10-05', amount: 9 });
  store.addEntry({ metricId: 'alphas', date: '2026-10-04', amount: 4 });
  const week = store.getWeek('2026-09-28');
  assert.equal(week.metrics.find(item => item.id === 'reading').actual, 3);
  assert.equal(week.metrics.find(item => item.id === 'reading').percent, 30);
  assert.equal(week.metrics.find(item => item.id === 'alphas').percent, 100);
  assert.equal(week.summary.actualHours, 3);
  assert.equal(week.summary.completed, 1);
  assert.equal(week.entries.length, 3);
});

test('Нормативы сохраняются после перезапуска, снятый норматив не делит на ноль', () => {
  const { store, file } = fixture();
  store.updateTargets('2026-09-28', { house_sale: 5, reading: null });
  const { entry } = store.addEntry({ metricId: 'house_sale', date: '2026-09-28', amount: 6 });
  const reopened = createStore(file);
  const sale = reopened.getWeek('2026-09-28').metrics.find(item => item.id === 'house_sale');
  assert.equal(sale.target, 5);
  assert.equal(sale.percent, 120);
  assert.equal(sale.remaining, 0);
  assert.equal(reopened.getWeek('2026-09-28').metrics.find(item => item.id === 'reading').percent, null);
  reopened.removeEntry(entry.id);
  assert.equal(reopened.getWeek('2026-09-28').summary.actualHours, 0);
});

test('Новая неделя наследует план; изменение старой не меняет уже созданную неделю', () => {
  const { store } = fixture();
  store.updateTargets('2026-09-28', { business: 7 });
  assert.equal(store.getWeek('2026-10-05').metrics.find(item => item.id === 'business').target, 7);
  store.updateTargets('2026-09-28', { business: 2 });
  assert.equal(store.getWeek('2026-10-05').metrics.find(item => item.id === 'business').target, 7);
});

test('Повторная загрузка одной задачи ботом не удваивает часы', () => {
  const { store } = fixture();
  const input = { metricId: 'guides', date: '2026-09-28', amount: 1.5, source: 'bot', externalId: 'task-137' };
  const first = store.addEntry(input);
  const again = store.addEntry(input);
  assert.equal(first.duplicate, false);
  assert.equal(again.duplicate, true);
  assert.equal(first.entry.id, again.entry.id);
  assert.equal(store.getWeek('2026-09-28').summary.actualHours, 1.5);
});

test('Ошибочные нормативы и записи отклоняются до изменения данных', () => {
  const { store } = fixture();
  assert.throws(() => store.updateTargets('2026-09-28', { reading: 5, alphas: 1.5 }));
  assert.equal(store.getWeek('2026-09-28').metrics.find(item => item.id === 'reading').target, 10);
  assert.throws(() => store.updateTargets('2026-09-28', { guides: 0 }));
  assert.throws(() => store.addEntry({ metricId: 'alphas', date: '2026-09-28', amount: 0.5 }));
  assert.throws(() => store.addEntry({ metricId: 'reading', date: '2026-02-30', amount: 2 }));
  assert.equal(store.getWeek('2026-09-28').entries.length, 0);
});
