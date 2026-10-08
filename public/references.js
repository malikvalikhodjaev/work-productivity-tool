const $ = id => document.getElementById(id);
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const dateLabel = value => new Date(value).toLocaleDateString('ru-RU', { timeZone: 'Asia/Tashkent' });
let data = null, group = 'Все', edited = null, dirty = false, saving = false, requestId = 0;
async function api(url, input) {
  const response = await fetch(url, input === undefined ? {} : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(input) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error ?? 'Не удалось прочитать источники.');
  return result;
}
function safeUrl(value) { try { const url = new URL(value); return ['https:', 'http:'].includes(url.protocol) && !url.username && !url.password; } catch { return false; } }
function history(item) {
  if (!item.revisions?.length) return '';
  return `<details><summary>История правок · ${item.revisions.length}</summary>${item.revisions.slice().reverse().map(version => `<div class="source-version"><p>${dateLabel(version.updatedAt)} · ${esc(version.title)}</p>${safeUrl(version.url) ? `<a href="${esc(version.url)}" target="_blank" rel="noopener noreferrer">${esc(version.url)}</a>` : '<span>Ссылка · No Data</span>'}<p class="source-original">${esc(version.note || 'No Data')}</p></div>`).join('')}</details>`;
}
function render() {
  if (!data) return;
  const query = $('sources-search').value.trim().toLocaleLowerCase('ru');
  const entries = data.entries.filter(item => (group === 'Все' || item.group === group) && [item.title, item.url, item.note, item.originalText, item.attribution].some(value => String(value ?? '').toLocaleLowerCase('ru').includes(query)));
  $('sources-count').textContent = `${data.entries.length} сохранено · показано ${entries.length}`;
  const bier = data.entries.find(item => item.id === 'ref-bier');
  if (bier?.attachment) $('bier-source-link').innerHTML = '<a href="/api/references/ref-bier/attachment" target="_blank" rel="noopener">Присланный скриншот ↗</a>';
  $('sources-groups').innerHTML = ['Все', ...data.groups].map(label => `<button type="button" data-source-group="${esc(label)}" aria-pressed="${label === group}">${esc(label)}${label === 'Все' ? '' : ` <span>${data.entries.filter(item => item.group === label).length}</span>`}</button>`).join('');
  $('sources-list').innerHTML = entries.length ? entries.map(item => `<article class="source-card"><div class="source-card-heading"><div><span class="source-group">${esc(item.group)}</span><h3>${esc(item.title)}</h3><p>${esc(item.attribution || 'Источник: No Data')}</p></div><div class="source-actions">${safeUrl(item.url) ? `<a href="${esc(item.url)}" target="_blank" rel="noopener noreferrer">Открыть ↗</a>` : '<span class="source-missing">Ссылка · No Data</span>'}${item.attachment ? `<a href="/api/references/${encodeURIComponent(item.id)}/attachment" target="_blank" rel="noopener">Скриншот ↗</a>` : ''}<button type="button" class="text-button" data-source-edit="${esc(item.id)}">Заметка / правка</button></div></div><details><summary>Зачем возвращаться · мысль и контекст</summary><div class="source-context">${item.note ? `<p class="source-note">${esc(item.note)}</p>` : '<p>No Data · заметка пока не задана.</p>'}${item.originalText ? `<details><summary>Исходная запись</summary><p class="source-original">${esc(item.originalText)}</p></details>` : ''}${safeUrl(item.url) ? `<p class="source-url"><a href="${esc(item.url)}" target="_blank" rel="noopener noreferrer">${esc(item.url)}</a></p>` : ''}${history(item)}<p class="source-origin">${esc(item.origin || 'No Data')} · добавлено ${dateLabel(item.createdAt)} · правок: ${item.revisions?.length ?? 0}</p></div></details></article>`).join('') : '<p class="section-note">No Data · нет источников по этому фильтру.</p>';
}
async function load() {
  const id = ++requestId;
  try { const result = await api('/api/references'); if (id !== requestId) return; data = result; $('sources-error').hidden = true; render(); }
  catch (error) { if (id === requestId) { $('sources-error').textContent = error.message; $('sources-error').hidden = false; } }
}
function openEditor(id = null) {
  edited = id ? data.entries.find(item => item.id === id) : null;
  $('source-editor-form').reset(); $('source-editor-error').hidden = true;
  $('source-editor-title').textContent = edited ? 'Источник и заметка' : 'Добавить ссылку или мысль';
  $('source-title').value = edited?.title ?? ''; $('source-url').value = edited?.url ?? '';
  $('source-attribution').value = edited?.attribution ?? ''; $('source-note').value = edited?.note ?? '';
  $('source-group').innerHTML = data.groups.map(label => `<option>${esc(label)}</option>`).join('');
  $('source-group').value = edited?.group ?? (group === 'Все' ? 'Мысли' : group);
  $('source-original').textContent = edited?.originalText || 'Исходная запись появится после первого сохранения.';
  dirty = false; $('source-editor').showModal();
}
function closeEditor() { if (!saving && (!dirty || window.confirm('Закрыть без сохранения заметки?'))) { dirty = false; $('source-editor').close(); } }
$('sources-search').addEventListener('input', render);
$('sources-groups').addEventListener('click', event => { const button = event.target.closest('[data-source-group]'); if (button) { group = button.dataset.sourceGroup; render(); } });
$('sources-list').addEventListener('click', event => { const button = event.target.closest('[data-source-edit]'); if (button) openEditor(button.dataset.sourceEdit); });
$('source-add').addEventListener('click', () => { if (data) openEditor(); });
$('sources-refresh').addEventListener('click', () => void load());
$('sources-data').addEventListener('click', () => window.dispatchEvent(new Event('rhythm:show-sources')));
$('source-editor-close').addEventListener('click', closeEditor);
$('source-editor').addEventListener('cancel', event => { event.preventDefault(); closeEditor(); });
$('source-editor-form').addEventListener('input', () => { dirty = true; });
$('source-editor-form').addEventListener('change', () => { dirty = true; });
$('source-editor-form').addEventListener('submit', async event => {
  event.preventDefault(); if (saving) return;
  const input = { title: $('source-title').value, url: $('source-url').value, group: $('source-group').value, attribution: $('source-attribution').value, note: $('source-note').value, expectedUpdatedAt: edited?.updatedAt ?? null };
  if (edited) input.id = edited.id;
  saving = true; $('source-editor-save').disabled = true;
  const fields = ['source-title', 'source-url', 'source-group', 'source-attribution', 'source-note']; fields.forEach(id => { $(id).disabled = true; });
  try { await api('/api/references', input); dirty = false; $('source-editor').close(); await load(); window.dispatchEvent(new Event('rhythm:sources-saved')); }
  catch (error) { $('source-editor-error').textContent = error.message; $('source-editor-error').hidden = false; }
  finally { saving = false; fields.forEach(id => { $(id).disabled = false; }); $('source-editor-save').disabled = false; }
});
window.addEventListener('beforeunload', event => { if (dirty) { event.preventDefault(); event.returnValue = ''; } });
window.addEventListener('rhythm:work-opened', () => void load());
window.addEventListener('focus', () => { if (!saving) void load(); });
void load();
