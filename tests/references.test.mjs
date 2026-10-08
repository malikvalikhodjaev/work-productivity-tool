import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createReferenceStore } from '../lib/references.mjs';

test('Источник сохраняет ссылку с якорем, исходную мысль и историю; старая вкладка не затирает правку', () => {
  const dir = mkdtempSync(join(tmpdir(), 'rhythm-references-'));
  try {
    const file = join(dir, 'references.json'), store = createReferenceStore(file);
    const input = { title: 'Моя мысль', group: 'Мысли', url: 'https://example.com/page#my-anchor', attribution: 'Из переписки', note: 'Проблема — разрыв между желаемым и текущим', expectedUpdatedAt: null };
    const first = store.save(input);
    assert.equal(first.url, input.url);
    const changed = store.save({ ...input, id: first.id, note: 'Вернуться при выборе главной работы', expectedUpdatedAt: first.updatedAt });
    assert.equal(changed.originalText, input.note);
    assert.equal(changed.revisions[0].note, input.note);
    assert.equal(changed.revisions[0].url, input.url);
    const raw = readFileSync(file, 'utf8');
    assert.throws(() => store.save({ ...input, id: first.id, expectedUpdatedAt: first.updatedAt }), /изменён/);
    for (const patch of [{ url: 'javascript:alert(1)' }, { url: 'file:///C:/secret' }, { url: 'https://user:pass@example.com' }, { url: 0 }, { title: '' }, { group: 'Нет такой' }]) assert.throws(() => store.save({ ...input, id: first.id, expectedUpdatedAt: changed.updatedAt, ...patch }));
    assert.equal(readFileSync(file, 'utf8'), raw);
    assert.deepEqual(createReferenceStore(file).view().entries, [changed]);
    const noLink = store.save({ ...input, title: 'Без ссылки', url: null });
    assert.equal(noLink.url, null);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('Просмотр не переписывает исходный JSON; вложение доступно только из каталога источников', () => {
  const dir = mkdtempSync(join(tmpdir(), 'rhythm-reference-raw-'));
  try {
    const file = join(dir, 'references.json');
    const raw = JSON.stringify({ version: 1, extra: 'сырой контекст', entries: [{ id: 'ref-image', title: 'Скриншот', group: 'Фокус', attachment: 'post.png' }, { id: 'ref-bad', attachment: '../outside.png' }] }, null, 4);
    writeFileSync(file, raw);
    mkdirSync(join(dir, 'reference-assets')); writeFileSync(join(dir, 'reference-assets', 'post.png'), 'test-image');
    const store = createReferenceStore(file); store.view();
    assert.equal(readFileSync(file, 'utf8'), raw);
    assert.equal(store.attachment('ref-image'), join(dir, 'reference-assets', 'post.png'));
    assert.equal(store.attachment('ref-bad'), null);
    assert.equal(store.attachment('missing'), null);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
