import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createStore, today, monday } from '../lib/store.mjs';
import { createWorkspaceStore, progress } from '../lib/workspace.mjs';
import { parseFinanceCsv } from '../lib/finance-csv.mjs';

function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'rhythm-workspace-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  let store;
  const workspace = createWorkspaceStore(join(dir, 'workspace.json'), () => store.getPortfolio());
  store = createStore(join(dir, 'dashboard.json'), { validateWorkRef: workspace.validateRef });
  return { dir, store, workspace };
}
function createSystem(workspace) {
  return workspace.mutate('saveSystem', { name: 'Тестовая система', characteristics: [
    { name: 'Полезный выпуск', unit: 'шт.', direction: 'up', baseline: 0, target: 10 },
    { name: 'Время ответа', unit: 'мин', direction: 'down', baseline: 20, target: 5 },
    { name: 'Доступность', unit: '%', direction: 'up', baseline: 90, target: 99 },
    { name: 'Расходы', unit: 'UZS', direction: 'down', baseline: 100, target: 120 }
  ] }).systems[0];
}
test('время вне нормативов входит в общий итог, но не выполняет норму; характер работы независим', t => {
  const { store } = fixture(t), date = today();
  store.addEntry({ metricId: 'reading', date, amount: 1, workType: 'Обучение' });
  const outside = store.addEntry({ metricId: null, allocation: 'outside', date, amount: 2, workType: 'Отдых' }).entry;
  store.addEntry({ metricId: 'business', date, amount: 3 });
  store.addEntry({ metricId: 'alphas', date, amount: 5 });
  const week = store.getWeek(date), time = store.getPeriod('today').time;
  assert.equal(week.summary.actualHours, 6);
  assert.equal(week.metrics.find(m => m.id === 'reading').actual, 1);
  assert.equal(time.total, 6);
  assert.deepEqual(Object.fromEntries(time.byAllocation.map(x => [x.key, x.hours])), { unplanned: 3, outside: 2, norm: 1 });
  assert.equal(time.byWorkType.find(x => x.key === 'Не разобрано').hours, 3);
  store.classifyEntry(outside.id, { metricId: 'reading', workType: 'Обучение' });
  assert.equal(store.getPeriod('today').time.total, 6);
  assert.equal(store.getWeek(date).metrics.find(m => m.id === 'reading').actual, 3);
  assert.equal(store.getWeek(date).entries.find(e => e.id === outside.id).classificationHistory[0].allocation, 'outside');
  assert.throws(() => store.classifyEntry(outside.id, { metricId: 'alphas' }), /количество/);
  assert.throws(() => store.addEntry({ metricId: 'reading', date, amount: 1, workRef: 'system:missing' }), /не найден/);
});
test('замеры системы общие с целями, ограничитель выявляет превышение; закрытие задачи не создаёт факт', t => {
  const { workspace, store, dir } = fixture(t);
  const system = createSystem(workspace), [priority,,,limit] = system.characteristics;
  store.updatePortfolio('createProject', { name: 'Проект', status: 'active', phase: 'pre_operation', zoneIds: ['customers'] });
  const projectId = store.getPortfolio().projects[0].id;
  workspace.mutate('saveLink', { ownerRef: `project:${projectId}`, systemId: system.id, notes: { [priority.id]: 'Увеличить полезный выпуск' } });
  workspace.mutate('saveGoal', { title: 'Промежуточный результат', characteristicId: priority.id, baseline: 0, target: 5, direction: 'up' });
  store.updatePortfolio('createTask', { projectId, title: 'Выпустить версию', beforeOperation: true });
  store.updatePortfolio('setTaskDone', { id: store.getPortfolio().tasks[0].id, done: true });
  assert.equal(workspace.view().goals[0].current, null);
  workspace.mutate('measure', { kind: 'characteristic', targetId: priority.id, value: 5, date: today(), evidence: 'Пять рабочих результатов', workRef: `project:${projectId}` });
  workspace.mutate('measure', { kind: 'characteristic', targetId: limit.id, value: 130, date: today(), evidence: 'Сверка расходов' });
  const result = workspace.view();
  assert.equal(result.systems[0].characteristics[0].percent, 50);
  assert.equal(result.goals[0].percent, 100);
  assert.equal(result.goals[0].reached, true);
  assert.equal(result.systems[0].characteristics[3].violation, true);
  assert.equal(result.systems[0].characteristics[1].current, null);
  assert.equal(createWorkspaceStore(join(dir,'workspace.json'), () => store.getPortfolio()).view().goals[0].current, 5);
  assert.throws(() => workspace.mutate('measure', { kind: 'goal', targetId: result.goals[0].id, value: 99, date: today(), evidence: 'Повтор' }), /связанной/);
  assert.deepEqual(progress(20, 10, 5, 'down'), { percent: 67, reached: false });
  assert.deepEqual(progress(null, 0, 0, 'up'), { percent: null, reached: true });
});
test('кейс вне проекта хранит диагностическую историю, закрытие требует результата', t => {
  const { workspace } = fixture(t);
  const item = workspace.mutate('saveCase', { title: 'Неясная ситуация', status: 'new' }).cases[0];
  assert.equal(item.projectId, null);
  workspace.mutate('reviewCase', { caseId: item.id, date: today(), facts: 'Наблюдение', unknowns: 'Причина', nextStep: 'Проверить гипотезу', nextReview: today() });
  assert.equal(workspace.view().reviews.length, 1);
  assert.equal(workspace.view().cases[0].nextStep, 'Проверить гипотезу');
  assert.throws(() => workspace.mutate('saveCase', { id: item.id, title: item.title, status: 'closed' }), /основание/);
});
test('CSV сохраняет Unicode и кавычки; импорт атомарный, повторы не удваивают деньги, валюты раздельны', t => {
  const { workspace, dir } = fixture(t), date = today();
  const csv = '\uFEFFexternalId,date,amount,currency,type,category,description\r\n' + `a,${date},12.50,USD,income,Работа,"Текст, 中文\nвторая строка"\r\n` + `b,${date},20,UZS,expense,Быт,Расход\r\n` + `c,${date},10,USD,transfer,Счета,Перевод`;
  const rows = parseFinanceCsv(csv);
  assert.match(rows[0].description, /中文\n/);
  assert.equal(workspace.importTransactions(rows,'test-app').valid,3);
  assert.equal(workspace.view().transactions.length,0);
  workspace.importTransactions(rows,'test-app',true);
  const before = readFileSync(join(dir,'workspace.json'),'utf8');
  assert.throws(() => workspace.importTransactions([...rows,{...rows[0],amount:15}],'test-app',true), /Импорт отменён/);
  assert.equal(readFileSync(join(dir,'workspace.json'),'utf8'),before);
  assert.equal(workspace.importTransactions(rows,'test-app',true).duplicates,3);
  const totals=workspace.finance(date,date).currencies;
  assert.equal(totals.find(x=>x.currency==='USD').net,12.5);
  assert.equal(totals.find(x=>x.currency==='USD').transfers,10);
  assert.equal(totals.find(x=>x.currency==='UZS').net,-20);
  assert.equal(workspace.view().transactions.length,3);
  const correctedId = workspace.view().transactions[0].id;
  workspace.correctTransaction(correctedId, { ...rows[0], amount: 14 });
  const corrected = workspace.view().transactions.find(t => t.id === correctedId);
  assert.equal(corrected.amountMinor, 1400);
  assert.equal(corrected.revisions[0].amountMinor, 1250);
  assert.throws(()=>parseFinanceCsv('externalId,date,amount,currency,type\na,2026-09-29,10,USD,"income'),/кавычки/);
  assert.throws(()=>parseFinanceCsv('date,amount\n2026-09-29,10'),/externalId/);
  assert.equal(workspace.finance('2000-01-01','2000-01-02').currencies.length,0);
});
