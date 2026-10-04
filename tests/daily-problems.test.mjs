import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createDailyProblemStore } from '../lib/daily-problems.mjs';
import { today } from '../lib/store.mjs';

test('одна проблема на дату, правки сохраняются, история переживает перезапуск', () => {
  const dir = mkdtempSync(join(tmpdir(), 'rhythm-problems-'));
  try {
    const file = join(dir, 'daily-problems.json');
    const store = createDailyProblemStore(file);
    assert.deepEqual(store.view().entries, []);
    const first = store.save({ date: today(), text: 'Хочу довести результат до эксплуатации; сейчас нет проверки.', expectedUpdatedAt: null });
    const other = store.save({ date: '2020-01-01', text: '旧的问题 — прошлый разрыв', expectedUpdatedAt: null });
    const next = store.save({ date: today(), text: '=Цель: проверить результат; факт: не назначен проверяющий.', expectedUpdatedAt: first.updatedAt });
    assert.equal(store.view().entries.length, 2);
    assert.equal(next.createdAt, first.createdAt);
    assert.equal(next.revisions[0].text, first.text);
    assert.equal(next.revisions[0].updatedAt, first.updatedAt);
    assert.notEqual(next.updatedAt, first.updatedAt);
    assert.throws(() => store.save({ date: today(), text: 'Устаревшая правка', expectedUpdatedAt: first.updatedAt }), /уже изменена/);
    assert.deepEqual(store.save({ date: today(), text: next.text, expectedUpdatedAt: next.updatedAt }), next);
    assert.deepEqual(createDailyProblemStore(file).view().entries, [next, other]);
    const table = readFileSync(join(dir, 'daily-problems.csv'), 'utf8');
    assert.ok(table.includes(other.text));
    assert.ok(table.includes(`"'=Цель:`));
    assert.equal(JSON.parse(readFileSync(file, 'utf8')).entries.find(item => item.date === today()).text[0], '=');
    const exposed = store.view();
    exposed.entries[0].revisions[0].text = 'Изменено извне';
    assert.equal(store.view().entries[0].revisions[0].text, first.text);
    for (const date of ['2026-02-30', '2999-01-01', '04.10.2026']) assert.throws(() => store.save({ date, text: 'Разрыв', expectedUpdatedAt: null }), /дату/);
    for (const text of ['', '   ', 'я'.repeat(2001), null]) assert.throws(() => store.save({ date: today(), text, expectedUpdatedAt: next.updatedAt }), /2000/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
