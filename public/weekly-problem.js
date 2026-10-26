const root = document.getElementById('weekly-problem');
const readonly = Boolean(document.querySelector('meta[name="dashboard-access"][content="viewer"]'));
let state = { week: null, entries: [] }, selected = null, baseline = null, saving = false;
const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Tashkent', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
const monday = date => { const d = new Date(`${date}T00:00:00Z`); d.setUTCDate(d.getUTCDate() - (d.getUTCDay() + 6) % 7); return d.toISOString().slice(0, 10); };
const current = () => monday(today());
root.innerHTML = `<div class="weekly-problem-heading"><h2>Главная проблема недели</h2><label>Неделя<select id="weekly-problem-week"></select></label></div><form id="weekly-problem-form"><label for="weekly-problem-text">The biggest problem of the week is…</label><textarea id="weekly-problem-text" rows="3" maxlength="2000" placeholder="Не записано" required></textarea><div class="weekly-problem-actions"><button type="submit" class="button primary">Сохранить</button><button type="button" id="weekly-problem-refresh" class="text-button">Обновить</button><button type="button" id="weekly-problem-export" class="text-button">Выгрузить историю</button><span id="weekly-problem-status" role="status"></span></div></form><details><summary>Как выбрать главное на неделю?</summary><p>Какой разрыв сейчас сильнее всего мешает нужному результату? Какую систему и её характеристику важно изменить? Что будет иначе к концу недели и по какому факту я это проверю?</p></details><details id="weekly-problem-reference" hidden><summary>Референс · Marc Andreessen</summary><blockquote></blockquote><p>Цитата прислана владельцем. Ссылка на первоисточник не указана.</p></details><details id="weekly-problem-revisions" hidden><summary>Предыдущие формулировки</summary><div></div></details>`;
const $ = id => document.getElementById(`weekly-problem-${id}`);
const key = week => `weekly-problem-composer:${week}`;
function draftWeeks() { try { return Object.keys(localStorage).filter(k => /^weekly-problem-composer:\d{4}-\d{2}-\d{2}$/.test(k)).map(k => k.slice('weekly-problem-composer:'.length)); } catch { return []; } }
function draft(week) { try { return JSON.parse(localStorage.getItem(key(week)) ?? 'null'); } catch { return null; } }
function status(text) { $('status').textContent = text; }
function keepDraft() {
  try { localStorage.setItem(key(selected), JSON.stringify({ text: $('text').value, expectedUpdatedAt: baseline })); }
  catch { status('Не удалось сохранить черновик в браузере. Скопируй текст перед закрытием.'); }
}
function render() {
  root.querySelector('.weekly-problem-comparison')?.remove();
  selected ??= current();
  const weeks = [...new Set([current(), selected, ...state.entries.map(e => e.week), ...draftWeeks()])].sort().reverse();
  $('week').replaceChildren(...weeks.map(week => { const option = document.createElement('option'); option.value = week; option.textContent = `${week}${week === current() ? ' · эта неделя' : ''}`; return option; }));
  $('week').value = selected;
  const entry = state.entries.find(e => e.week === selected), composer = draft(selected);
  baseline = composer ? composer.expectedUpdatedAt : entry?.updatedAt ?? null;
  $('text').value = composer ? composer.text : entry?.text ?? '';
  status(composer ? 'Черновик в браузере · нажми «Сохранить»' : entry ? 'Сохранено' : 'проблема недели не записана');
  $('revisions').hidden = !entry?.revisions?.length;
  $('revisions').querySelector('div').replaceChildren(...(entry?.revisions ?? []).toReversed().map(revision => { const p = document.createElement('p'); p.textContent = `${revision.updatedAt}\n${revision.text}`; return p; }));
  $('text').readOnly = readonly;
  $('form').querySelector('[type=submit]').disabled = readonly || saving;
}
async function load() {
  try {
    const response = await fetch('/api/weekly-problems');
    const result = await response.json();
    if (!response.ok) throw new Error(result.error ?? 'Не удалось загрузить проблему недели.');
    state = result;
    render();
  } catch (error) { render(); status(`${error.message} Черновик остаётся в браузере.`); }
}
$('week').addEventListener('change', () => { selected = $('week').value; render(); });
$('text').addEventListener('input', keepDraft);
$('refresh').addEventListener('click', load);
$('form').addEventListener('submit', async event => {
  event.preventDefault();
  if (saving || readonly) return;
  const week = selected, text = $('text').value;
  keepDraft();
  saving = true;
  $('week').disabled = true;
  $('text').readOnly = true;
  $('form').querySelector('[type=submit]').disabled = true;
  try {
    const response = await fetch('/api/weekly-problems', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ week, text, expectedUpdatedAt: baseline }) });
    const result = await response.json();
    if (!response.ok) {
      if (response.status === 409) {
        const latest = await fetch('/api/weekly-problems');
        if (latest.ok) {
          const data = await latest.json(), entry = data.entries.find(e => e.week === week);
          const comparison = document.createElement('div'), text = document.createElement('p'), accept = document.createElement('button');
          comparison.className = 'weekly-problem-comparison';
          text.textContent = `На сервере сейчас: ${entry?.text ?? 'Не записано'}`;
          accept.type = 'button'; accept.className = 'button secondary'; accept.textContent = 'Сравнил · сохранить мою формулировку следующей правкой';
          accept.addEventListener('click', () => { baseline = entry?.updatedAt ?? null; keepDraft(); comparison.remove(); status('Твоя формулировка сохранена в черновике. Нажми «Сохранить», чтобы добавить новую правку.'); });
          comparison.append(text, accept); root.querySelector('.weekly-problem-comparison')?.remove(); $('form').after(comparison);
        }
      }
      throw new Error(result.error ?? 'Не удалось сохранить.');
    }
    state = result.weeklyProblems;
    try { localStorage.removeItem(key(week)); } catch { /* Saved on server; retain the browser draft if storage is unavailable. */ }
    root.querySelector('.weekly-problem-comparison')?.remove();
    render();
    status('Сохранено');
  } catch (error) { status(`${error.message} Текст остаётся в поле. Не закрывай его до сохранения; при конфликте сравни с серверной формулировкой ниже.`); }
  finally { saving = false; $('week').disabled = false; $('text').readOnly = readonly; $('form').querySelector('[type=submit]').disabled = readonly; }
});
$('export').addEventListener('click', () => {
  const url = URL.createObjectURL(new Blob([JSON.stringify({ ...state, browserDrafts: draftWeeks().map(week => ({ week, ...draft(week) })).filter(e => e.text != null) }, null, 2)], { type: 'application/json' }));
  const link = document.createElement('a'); link.href = url; link.download = 'weekly-problems.json'; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
});
fetch('/api/references').then(r => r.ok ? r.json() : {}).then(data => {
  const ref = data.entries?.find(e => e.title === 'Marc Andreessen · главная проблема недели');
  if (!ref) return;
  $('reference').querySelector('blockquote').textContent = ref.originalText ?? ref.note ?? '';
  $('reference').hidden = false;
}).catch(() => {});
await load();
