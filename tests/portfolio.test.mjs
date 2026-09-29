import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { createStore } from '../lib/store.mjs';

function fixture() {
  const file = path.join(mkdtempSync(path.join(tmpdir(), 'rhythm-projects-')), 'dashboard.json');
  const store = createStore(file);
  store.updatePortfolio('createProject', { name: 'Тестовый проект', status: 'active', phase: 'pre_operation', zoneIds: ['customers', 'economics', 'operators'] });
  const project = store.getPortfolio().projects[0];
  for (const zone of project.zones) {
    store.updatePortfolio('createAlpha', { projectId: project.id, zoneId: zone.id, typeName: zone.typeName, uniqueName: `${zone.typeName} тестового проекта`, description: 'Объект для проверки.', state: 'empty' });
  }
  return { file, store, projectId: project.id };
}

test('Существующие нормативы и записи сохраняются; перед расширением делается точная копия исходника', () => {
  const file = path.join(mkdtempSync(path.join(tmpdir(), 'rhythm-migration-')), 'dashboard.json');
  const original = JSON.stringify({ version: 1, plans: { '2026-09-28': { guides: 12, mentor: 3, reading: 10, house_sale: null, business: 4, work_support: null, household: null, other: null, alphas: 5 } }, entries: [{ id: 'manual-1', metricId: 'reading', amount: 2, date: '2026-09-28', source: 'manual', title: 'Исходная запись', createdAt: '2026-09-28T08:00:00Z' }] });
  writeFileSync(file, original);
  const store = createStore(file);
  assert.equal(readFileSync(`${file}.before-projects.json`, 'utf8'), original);
  assert.equal(store.getWeek('2026-09-28').metrics.find(item => item.id === 'guides').target, 12);
  assert.equal(store.getWeek('2026-09-28').summary.actualHours, 2);
  assert.equal(store.getPortfolio().summary.gapZones, 0);
  assert.equal(store.getPortfolio().summary.activeProjects, 0);
  assert.equal(store.getPortfolio().summary.beforeOperationTasks, 0);
});

test('Заполненный слот считается один раз в своей неделе; состояние требует отдельного подтверждения', () => {
  const { store } = fixture();
  const alpha = store.getPortfolio().alphas[0];
  store.updateTargets('2026-09-28', { alphas: 2 });
  const input = { ...alpha, state: 'described', filledDate: '2026-09-28', description: 'Потребности конкретных клиентов описаны.' };
  store.updatePortfolio('updateAlpha', input);
  store.updatePortfolio('updateAlpha', { ...input, nextStep: 'Провести обсуждение.' });
  assert.equal(store.getWeek('2026-09-28').metrics.find(item => item.id === 'alphas').actual, 1);
  assert.equal(store.getWeek('2026-10-05').metrics.find(item => item.id === 'alphas').actual, 0);
  assert.equal(store.getPortfolio().summary.gapZones, 3);
  store.updatePortfolio('updateAlpha', { ...input, state: 'verified', criteria: 'Потребность обсуждена с клиентами.', evidence: 'Итоги разговоров записаны.' });
  assert.equal(store.getPortfolio().summary.gapZones, 2);
});

test('Пустая подальфа оставляет пробел даже при подтверждённой родительской альфе; циклы отклоняются', () => {
  const { store } = fixture();
  const parent = store.getPortfolio().alphas[0];
  const ready = { ...parent, state: 'verified', criteria: 'Критерий', evidence: 'Свидетельство', filledDate: '2026-09-28' };
  store.updatePortfolio('updateAlpha', ready);
  store.updatePortfolio('createAlpha', { projectId: parent.projectId, parentId: parent.id, zoneId: parent.zoneId, typeName: 'Сегмент клиентов', uniqueName: 'Сегмент А', state: 'empty' });
  const child = store.getPortfolio().alphas.find(alpha => alpha.parentId === parent.id);
  assert.equal(store.getPortfolio().summary.gapZones, 3);
  assert.throws(() => store.updatePortfolio('updateAlpha', { ...ready, parentId: child.id }));
  store.updatePortfolio('updateAlpha', { ...child, state: 'verified', description: 'Конкретный сегмент', criteria: 'Потребность подтверждена', evidence: 'Результат обсуждения', filledDate: '2026-09-28' });
  assert.equal(store.getPortfolio().summary.gapZones, 2);
  assert.equal(store.getWeek('2026-09-28').metrics.find(item => item.id === 'alphas').actual, 2);
});

test('Счётчик до эксплуатации исключает закрытые задачи и проекты на паузе, но не скрывает задачи после запуска', () => {
  const { store, projectId } = fixture();
  store.updatePortfolio('createTask', { projectId, title: 'Обсудить с клиентами', beforeOperation: true });
  store.updatePortfolio('createTask', { projectId, title: 'Текущая поддержка', beforeOperation: false });
  assert.equal(store.getPortfolio().summary.beforeOperationTasks, 1);
  assert.equal(store.getPortfolio().summary.openTasks, 2);
  const project = store.getPortfolio().projects[0];
  const input = { ...project, zoneIds: project.zones.map(zone => zone.id) };
  store.updatePortfolio('updateProject', { ...input, phase: 'operation' });
  assert.equal(store.getPortfolio().summary.beforeOperationTasks, 1);
  store.updatePortfolio('updateProject', { ...input, status: 'paused' });
  assert.equal(store.getPortfolio().summary.activeProjects, 0);
  assert.equal(store.getPortfolio().summary.beforeOperationTasks, 0);
  store.updatePortfolio('updateProject', input);
  const task = store.getPortfolio().tasks.find(task => task.beforeOperation);
  store.updatePortfolio('setTaskDone', { id: task.id, done: true });
  assert.equal(store.getPortfolio().summary.beforeOperationTasks, 0);
  store.updatePortfolio('setTaskDone', { id: task.id, done: false });
  assert.equal(store.getPortfolio().summary.beforeOperationTasks, 1);
});

test('Пользовательские зоны, уникальные имена и сохранение проектов после перезапуска', () => {
  const { store, file, projectId } = fixture();
  store.updatePortfolio('createProject', { name: 'Другой проект', status: 'active', phase: 'pre_operation', zoneIds: ['customers'] });
  const project = store.getPortfolio().projects.find(project => project.id !== projectId);
  store.updatePortfolio('addZone', { projectId: project.id, title: 'Команда', hint: 'Понятны роли.' });
  const input = { projectId: project.id, zoneId: 'customers', typeName: 'Клиентура', uniqueName: 'Клиенты нового проекта', state: 'empty' };
  store.updatePortfolio('createAlpha', input);
  assert.throws(() => store.updatePortfolio('createAlpha', input));
  assert.equal(createStore(file).getPortfolio().summary.activeProjects, 2);
  assert.equal(createStore(file).getPortfolio().projects.find(item => item.id === project.id).zones.length, 2);
  assert.equal(existsSync(file), true);
});
