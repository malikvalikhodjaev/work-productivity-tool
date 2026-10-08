const $ = id => document.getElementById(id);
const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const params = new URLSearchParams(location.search);
const embedded = params.get('embedded') === '1';
if (embedded) document.documentElement.classList.add('embedded');
const notifyParent = type => { if (embedded) parent.postMessage({ type }, location.origin); };
const fields = ['projectId','uniqueName','description','evidence','criteria','nextStep','reviewDate','typeName','adaptedAlpha','area','stateLabel','whyImportant','source','metaAdaptation','systemTime','attention','zoneId','parentId','state','filledDate'];
let portfolio; let reference = []; let selectedId = null; let selectedRevision = 0; let dirty = false; let saving = false; let pendingBackup = null;
let focusResult = null;
const dateLabel = value => value ? new Intl.DateTimeFormat('ru-RU', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '';
const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Tashkent', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
async function request(url, input) {
  const response = await fetch(url, input ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(input) } : {});
  const value = await response.json();
  if (!response.ok) throw new Error(value.error ?? 'Не удалось выполнить запрос.');
  return value;
}
function notice(message, error = false) { $('notice').textContent = message; $('notice').classList.toggle('error', error); $('notice').hidden = false; }
function options(element, values, selected) { element.innerHTML = values.map(item => `<option value="${escape(item.id)}">${escape(item.name ?? item.title)}</option>`).join(''); element.value = selected ?? values[0]?.id ?? ''; }
function extraOption(element, value) { if (value && ![...element.options].some(option => option.value === value)) element.add(new Option(value, value)); element.value = value ?? ''; }
function renderProjects() {
  const filter = $('project-filter').value;
  options($('project-filter'), [{id:'',name:'Все проекты'}, ...portfolio.projects], filter);
  options($('projectId'), portfolio.projects);
  options($('state'), portfolio.states);
  $('new').disabled = !portfolio.projects.length;
}
function renderList() {
  const query = $('search').value.trim().toLocaleLowerCase('ru'); const project = $('project-filter').value;
  const entries = portfolio.alphas.filter(alpha => (!project || alpha.projectId === project) && (!query || [alpha.uniqueName,alpha.typeName,alpha.description,alpha.evidence,alpha.nextStep].some(value => value?.toLocaleLowerCase('ru').includes(query))) && (!$('due-only').checked || (alpha.reviewDate && alpha.reviewDate <= today() && alpha.attention !== 'Закрыт')));
  $('count').textContent = `Объектов: ${entries.length} из ${portfolio.alphas.length}`;
  $('objects').innerHTML = entries.length ? entries.map(alpha => {
    const projectName = portfolio.projects.find(project => project.id === alpha.projectId)?.name ?? '';
    const due = alpha.reviewDate && alpha.reviewDate <= today() && alpha.attention !== 'Закрыт';
    return `<button type="button" class="object ${alpha.id === selectedId ? 'active' : ''}" data-id="${escape(alpha.id)}" aria-pressed="${alpha.id === selectedId}"><strong>${escape(alpha.uniqueName || alpha.typeName)}</strong><span class="object-sub">${escape(projectName)}${alpha.typeName ? ` · ${escape(alpha.typeName)}` : ''}</span>${alpha.reviewDate ? `<span class="${due ? 'due' : 'object-sub'}">${due ? 'Пора вернуться' : 'Вернуться'}: ${escape(alpha.reviewDate)}</span>` : ''}</button>`;
  }).join('') : '<p class="muted">Нет объектов по выбранному фильтру.</p>';
}
function selectZone(projectId, zoneId, parentId) {
  const project = portfolio.projects.find(project => project.id === projectId);
  options($('zoneId'), project?.zones ?? [], zoneId ?? project?.zones[0]?.id);
  options($('parentId'), [{id:'',name:'Самостоятельный объект'}, ...portfolio.alphas.filter(alpha => alpha.projectId === projectId && alpha.id !== selectedId).map(alpha => ({id:alpha.id,name:alpha.uniqueName || alpha.typeName}))], parentId ?? '');
}
function referenceOptions() {
  const alpha = $('typeName').value.trim();
  const states = [...new Set(reference.filter(row => row.alpha === alpha && row.state).map(row => row.state))];
  $('alpha-states').innerHTML = states.map(state => `<option value="${escape(state)}"></option>`).join('');
  $('reference-hint').textContent = states.length ? `В твоём локальном справочнике: ${states.length} состояний этой альфы. Точное название можно выбрать в поле состояния.` : 'Справочник взят из существующего alpha-reference.json. Можно использовать своё имя и состояние.';
}
const draftKey = () => `rhythm-alpha-draft:${selectedId ?? 'new'}`;
function values() { return Object.fromEntries(fields.map(id => [id, $(id).value])); }
function setValues(input) {
  selectZone(input.projectId, input.zoneId, input.parentId);
  for (const id of fields) {
    if ($(id).tagName === 'SELECT') extraOption($(id), input[id]);
    else $(id).value = input[id] ?? '';
  }
  referenceOptions();
}
function renderFocus() {
  $('alpha-make-focus').disabled = !selectedId || dirty || saving;
  const selected = selectedId && focusResult?.workRef === `alpha:${selectedId}`;
  const label = { planned: 'Выбрано', in_progress: 'В работе', blocked: 'Есть препятствие', ready: 'Готово' };
  $('alpha-focus-state').textContent = selected ? `Главное сегодня · ${label[focusResult.status]} · ${focusResult.progress === null ? 'No Data' : `${focusResult.progress}%`}` : dirty || !selectedId ? 'Сначала сохрани запись' : 'Можно выбрать эту работу главной на день';
}
async function loadFocus() {
  try { const data = await request('/api/daily-results'); focusResult = data.entries.find(item => item.date === data.today) ?? null; }
  catch { focusResult = null; }
  renderFocus();
}
function updateDirty() { $('save-state').textContent = dirty ? 'Есть несохранённые изменения' : 'Без изменений'; $('save-state').classList.toggle('dirty', dirty); renderFocus(); }
function keepDraft() {
  dirty = true; updateDirty();
  try { localStorage.setItem(draftKey(), JSON.stringify({ input: values(), revision: selectedRevision, at: new Date().toISOString() })); }
  catch { notice('Черновик браузера недоступен. Нажми «Сохранить запись», чтобы записать данные в файл.', true); }
}
function leaveEditor() { return !dirty || window.confirm('Есть несохранённая запись. Перейти к другому объекту? Черновик останется в этом браузере.'); }
async function historyFor(alphaId) {
  if (!alphaId) { $('history').innerHTML = '<p class="muted">История появится после первого сохранения.</p>'; $('history-count').textContent = ''; return; }
  try {
    const response = await request(`/api/alphas/history?id=${encodeURIComponent(alphaId)}`);
    if (selectedId !== alphaId) return;
    $('history-count').textContent = `(${response.entries.length})`;
    $('history').innerHTML = response.entries.length ? response.entries.slice().sort((a,b) => b.at.localeCompare(a.at)).map(entry => {
      const snapshot = entry.snapshot; const labels = {description:'Моя запись',evidence:'Факт / свидетельство',criteria:'Ожидаемое состояние / критерий',nextStep:'Следующий ход',reviewDate:'Когда вернуться'};
      return `<article class="history-entry"><strong>${escape(dateLabel(entry.at))} · ${({baseline:'До первого изменения',create:'Создано',edit:'Изменено',import:'Импорт'})[entry.action] ?? 'Сохранено'}</strong><dl>${Object.entries(labels).filter(([key]) => snapshot[key]).map(([key,label]) => `<dt>${label}</dt><dd>${escape(snapshot[key])}</dd>`).join('')}</dl><details><summary>Все поля этой версии</summary><dl>${fields.filter(key => snapshot[key]).map(key => `<dt>${escape($(key).closest('label')?.childNodes[0]?.textContent.trim() ?? key)}</dt><dd>${escape(snapshot[key])}</dd>`).join('')}</dl></details></article>`;
    }).join('') : '<p class="muted">Ещё не было содержательных правок в моделерe. Просмотр и повторное сохранение без изменений не добавляют версии.</p>';
  } catch(error) { notice(error.message, true); }
}
function openEditor(alphaId, ask = true) {
  if (saving || (ask && !leaveEditor())) return;
  const alpha = alphaId ? portfolio.alphas.find(item => item.id === alphaId) : null;
  selectedId = alpha?.id ?? null; selectedRevision = alpha?.revision ?? 0; dirty = false;
  const projectId = alpha?.projectId ?? ($('project-filter').value || portfolio.projects[0]?.id);
  if (!projectId) { $('blank').hidden = false; $('editor-form').hidden = true; return; }
  $('blank').hidden = true; $('editor-form').hidden = false;
  setValues({ state:'empty', zoneId:portfolio.projects.find(item => item.id === projectId)?.zones[0]?.id, ...alpha, projectId });
  $('projectId').disabled = Boolean(alpha);
  $('editor-title').textContent = alpha ? alpha.uniqueName || alpha.typeName : 'Новый объект';
  $('object-meta').textContent = portfolio.projects.find(project => project.id === projectId)?.name ?? '';
  $('saved-at').textContent = alpha ? `Последнее изменение: ${dateLabel(alpha.updatedAt)}` : 'Достаточно проекта и имени объекта';
  $('history-panel').open = false; $('draft-banner').hidden = true;
  try { $('draft-banner').hidden = !localStorage.getItem(draftKey()); } catch {}
  updateDirty(); renderList(); void historyFor(selectedId); void loadFocus();
}
async function save(event) {
  event?.preventDefault(); if (saving || $('editor-form').hidden || !$('editor-form').reportValidity()) return;
  saving = true; renderFocus(); $('save').disabled = true; $('save-state').textContent = 'Сохраняю в локальный файл…';
  for (const id of [...fields,'new','export','import']) $(id).disabled = true;
  const key = draftKey(); const priorId = selectedId; let savedId;
  try {
    const input = values(); input.parentId ||= null; input.filledDate ||= null; input.reviewDate ||= null;
    if (selectedId) { input.id = selectedId; input.expectedRevision = selectedRevision; }
    const result = await request('/api/portfolio', {action:selectedId ? 'updateAlpha' : 'createAlpha',input});
    savedId = priorId ?? result.alphas.find(alpha => !portfolio.alphas.some(previous => previous.id === alpha.id))?.id;
    portfolio = result; dirty = false;
    try { localStorage.removeItem(key); } catch {}
    renderProjects(); notice('Запись сохранена в локальном файле.');
  } catch(error) { notice(error.message, true); updateDirty(); }
  finally { saving = false; renderFocus(); for (const id of [...fields,'export','import']) $(id).disabled = false; $('projectId').disabled = Boolean(selectedId); $('new').disabled = !portfolio.projects.length; $('save').disabled = false; if (savedId) openEditor(savedId, false); }
  if (savedId) notifyParent('rhythm:alpha-saved');
}
async function selectProject(projectId) {
  if (!portfolio || saving) return false;
  if ($('project-filter').value === projectId && (!selectedId || portfolio.alphas.find(a=>a.id===selectedId)?.projectId === projectId)) return true;
  if (!leaveEditor()) return false;
  if (!portfolio.projects.some(p=>p.id===projectId)) portfolio = await request('/api/portfolio');
  renderProjects(); $('project-filter').value = projectId; $('search').value = ''; $('due-only').checked = false;
  openEditor(portfolio.alphas.find(a=>a.projectId===projectId)?.id ?? null, false);
  return true;
}
window.rhythmAlphaModeler = {
  get currentProjectId() { return $('project-filter').value; },
  selectProject,
  async refresh() {
    if (!portfolio || dirty || saving) return;
    const priorId = selectedId, filter = $('project-filter').value;
    portfolio = await request('/api/portfolio'); renderProjects(); $('project-filter').value = filter;
    openEditor(portfolio.alphas.find(a=>a.id===priorId && (!filter || a.projectId===filter))?.id ?? portfolio.alphas.find(a=>!filter || a.projectId===filter)?.id ?? null, false);
  }
};
if (embedded) {
  const resize = () => parent.postMessage({ type: 'rhythm:alpha-height', height: Math.ceil(document.querySelector('main').getBoundingClientRect().height) + 4 }, location.origin);
  new ResizeObserver(resize).observe(document.querySelector('main'));
  $('project-filter').closest('label').hidden = true;
}
async function load() {
  portfolio = await request('/api/portfolio'); renderProjects(); renderList();
  try {
    const imported = await request('/api/imported-data'); reference = imported.reference.rows ?? [];
    $('alpha-names').innerHTML = [...new Set(reference.filter(row => row.alpha).map(row => row.alpha))].map(alpha => `<option value="${escape(alpha)}"></option>`).join('');
  } catch { notice('Локальный справочник сейчас недоступен. Свои записи можно сохранять.', true); }
  const project = params.get('project'), requestedAlpha = portfolio.alphas.find(item => item.id === params.get('alpha') && (!project || item.projectId === project));
  if (requestedAlpha) { $('project-filter').value = requestedAlpha.projectId; openEditor(requestedAlpha.id, false); }
  else if (project && portfolio.projects.some(p=>p.id===project)) { $('project-filter').value = project; openEditor(portfolio.alphas.find(a=>a.projectId===project)?.id ?? null, false); }
  else openEditor(portfolio.alphas[0]?.id ?? null, false);
  notifyParent('rhythm:alpha-ready');
}
$('objects').addEventListener('click', event => { const button = event.target.closest('[data-id]'); if (button) openEditor(button.dataset.id); });
for (const id of ['project-filter','search','due-only']) $(id).addEventListener(id === 'search' ? 'input' : 'change', renderList);
$('new').addEventListener('click', () => { openEditor(null); if (!saving && !selectedId) $('uniqueName').focus(); });
$('alpha-make-focus').addEventListener('click', () => {
  if (dirty || saving || !selectedId) return;
  const alpha = portfolio.alphas.find(item => item.id === selectedId);
  const work = { workRef: `alpha:${alpha.id}`, text: alpha.nextStep || `Продвинуть ${alpha.uniqueName || alpha.typeName}`, whyImportant: alpha.whyImportant, nextStep: alpha.nextStep };
  if (embedded) parent.postMessage({ type: 'rhythm:focus-object', work }, location.origin);
  else location.href = `/?focusAlpha=${encodeURIComponent(alpha.id)}#work`;
});
window.addEventListener('message', event => { if (embedded && event.origin === location.origin && event.source === parent && event.data?.type === 'rhythm:work-updated') void loadFocus(); });
window.addEventListener('focus', () => void loadFocus());
$('projectId').addEventListener('change', () => { selectZone($('projectId').value); $('object-meta').textContent = portfolio.projects.find(project => project.id === $('projectId').value)?.name ?? ''; });
$('typeName').addEventListener('input', referenceOptions);
$('editor-form').addEventListener('input', keepDraft); $('editor-form').addEventListener('change', keepDraft); $('editor-form').addEventListener('submit', save);
$('restore-draft').addEventListener('click', () => {
  try {
    const draft = JSON.parse(localStorage.getItem(draftKey()));
    if (!draft?.input || !portfolio.projects.some(project => project.id === draft.input.projectId)) throw new Error('Проект черновика не найден.');
    if (selectedId && draft.input.projectId !== $('projectId').value) throw new Error('Черновик относится к другому проекту.');
    setValues(draft.input); selectedRevision = draft.revision ?? 0; dirty = true; updateDirty(); $('draft-banner').hidden = true;
    notice('Черновик восстановлен. Проверь текст и сохрани запись.');
  } catch(error) { notice(`Не удалось восстановить черновик: ${error.message}`, true); }
});
$('discard-draft').addEventListener('click', () => { try { localStorage.removeItem(draftKey()); $('draft-banner').hidden = true; } catch(error) { notice(error.message, true); } });
window.addEventListener('beforeunload', event => { if (dirty) { event.preventDefault(); event.returnValue = ''; } });
window.addEventListener('keydown', event => { if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') { event.preventDefault(); void save(); } });
$('export').addEventListener('click', async () => {
  try { const backup = await request('/api/alphas/export'); const url = URL.createObjectURL(new Blob([JSON.stringify(backup,null,2)],{type:'application/json'})); const link = document.createElement('a'); link.href = url; link.download = `alphas-${today()}.json`; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); notice(dirty ? 'Экспорт сохранённых объектов готов. Текущий черновик сначала нужно сохранить.' : 'Экспорт сохранённых объектов и истории готов.'); }
  catch(error) { notice(error.message,true); }
});
$('import').addEventListener('click', () => { $('import-dialog').showModal(); });
$('import-cancel').addEventListener('click', () => $('import-dialog').close());
$('import-file').addEventListener('change', async () => {
  pendingBackup = null; $('import-commit').disabled = true; $('import-preview').textContent = 'Проверяю файл…';
  try {
    const file = $('import-file').files[0]; if (!file) { $('import-preview').textContent = ''; return; }
    if (file.size > 3 * 1024 * 1024) throw new Error('Выбери файл до 3 МБ.');
    const backup = JSON.parse(await file.text()); const preview = await request('/api/alphas/import',{backup});
    pendingBackup = backup;
    $('import-preview').innerHTML = `<p>Добавится: <strong>${preview.added}</strong>. Уже есть: ${preview.unchanged}. Пропущено отличающихся: ${preview.conflicts.length}.</p>${preview.conflicts.length ? `<ul>${preview.conflicts.map(item => `<li>${escape(item.name)}</li>`).join('')}</ul>` : ''}`;
    $('import-commit').disabled = !preview.added;
  } catch(error) { $('import-preview').textContent = `Ошибка проверки: ${error.message}`; }
});
$('import-commit').addEventListener('click', async () => {
  if (!pendingBackup || !leaveEditor()) return; $('import-commit').disabled = true;
  try {
    const report = await request('/api/alphas/import',{backup:pendingBackup,commit:true}); const priorId = selectedId;
    portfolio = await request('/api/portfolio'); renderProjects(); openEditor(priorId ?? portfolio.alphas.at(-1)?.id,false);
    $('import-dialog').close(); pendingBackup = null; notice(`Добавлено объектов: ${report.added}. Пропущено отличающихся: ${report.conflicts.length}.`); notifyParent('rhythm:alpha-saved');
  } catch(error) { $('import-preview').textContent = error.message; $('import-commit').disabled = false; }
});
load().catch(error => { notice(error.message,true); $('objects').textContent = 'Не удалось загрузить локальные данные. Обнови страницу после запуска дашборда.'; });
