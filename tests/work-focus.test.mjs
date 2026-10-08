import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createDailyResultStore } from '../lib/daily-results.mjs';

const validateWorkRef = ref => {
  if (ref === null || ref === '') return null;
  if (ref !== 'alpha:demo') throw new Error('Связанный объект не найден.');
  return ref;
};

test('Работа дня хранит связь, прогресс и историю; готовность требует подтверждения', () => {
  const dir = mkdtempSync(join(tmpdir(), 'rhythm-work-focus-'));
  try {
    const file = join(dir, 'daily-results.json'), store = createDailyResultStore(file, { validateWorkRef });
    const input = { date: '2026-09-30', text: 'Проверить первую версию', status: 'in_progress', progress: 40, evidence: '', workRef: 'alpha:demo', whyImportant: 'Уменьшить время до использования', nextStep: 'Показать пользователю', focusWindow: '10:00–11:00', expectedUpdatedAt: null };
    const first = store.save(input), original = readFileSync(file, 'utf8');
    for (const patch of [{ progress: 101 }, { progress: 1.5 }, { progress: '40' }, { progress: 100 }, { workRef: 'alpha:missing' }, { status: 'ready', evidence: '' }, { status: 'ready', progress: 999, evidence: 'Получен отзыв' }]) {
      assert.throws(() => store.save({ ...input, expectedUpdatedAt: first.updatedAt, ...patch }));
      assert.equal(readFileSync(file, 'utf8'), original);
    }
    assert.deepEqual(store.save({ ...input, expectedUpdatedAt: first.updatedAt }), first);
    const blocked = store.save({ ...input, status: 'blocked', nextStep: 'Дождаться доступа', expectedUpdatedAt: first.updatedAt });
    assert.equal(blocked.progress, 40);
    assert.equal(blocked.revisions[0].nextStep, input.nextStep);
    assert.equal(blocked.revisions[0].workRef, 'alpha:demo');
    assert.throws(() => store.save({ ...input, expectedUpdatedAt: first.updatedAt }), /изменён/);
    const ready = store.save({ ...input, status: 'ready', evidence: 'Проверено пользователем', expectedUpdatedAt: blocked.updatedAt });
    assert.equal(ready.progress, 100);
    assert.equal(ready.revisions[1].status, 'blocked');
    assert.deepEqual(createDailyResultStore(file, { validateWorkRef }).view().entries, [ready]);
    const nextDay = store.save({ ...input, date: '2026-10-01', status: 'planned', progress: null, workRef: null });
    assert.equal(nextDay.progress, null);
    assert.equal(nextDay.revisions.length, 0);
    const csv = readFileSync(join(dir, 'daily-results.csv'), 'utf8');
    assert.ok(csv.includes('progress_percent') && csv.includes('alpha:demo') && csv.includes('10:00–11:00'));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('Просмотр прежнего JSON добавляет представление прогресса без изменения исходного файла', () => {
  const dir = mkdtempSync(join(tmpdir(), 'rhythm-work-legacy-'));
  try {
    const file = join(dir, 'daily-results.json');
    const raw = JSON.stringify({ version: 1, untouched: 'сырой контекст', entries: [{ date: '2026-09-30', text: 'Старый результат', status: 'ready', evidence: 'Проверено', createdAt: '2026-09-30T01:00:00Z', updatedAt: '2026-09-30T01:00:00Z', revisions: [] }] }, null, 4);
    writeFileSync(file, raw);
    const store = createDailyResultStore(file, { validateWorkRef });
    assert.equal(store.view().entries[0].progress, 100);
    assert.equal(store.view().entries[0].workRef, null);
    assert.equal(readFileSync(file, 'utf8'), raw);
    const previous = store.view().entries[0];
    store.save({ ...previous, status: 'planned', progress: null, expectedUpdatedAt: previous.updatedAt });
    assert.equal(JSON.parse(readFileSync(file, 'utf8')).untouched, 'сырой контекст');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
