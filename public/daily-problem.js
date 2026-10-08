const $ = id => document.getElementById(id);
let entries = [];
let savedEntry = null;
let loading = false;
let saving = false;
let dirty = false;
let requestId = 0;
let currentDay = null;
window.rhythmDailyProblem = { isDirty: () => dirty, isSaving: () => saving };
window.addEventListener('rhythm:work-date-selected', event => {
  if ((dirty || saving) && !event.detail.discard) return;
  $('daily-problem-date').value = event.detail.date; selectDate();
});

function setStatus(text, error = false) {
  $('daily-problem-status').textContent = text;
  $('daily-problem-status').classList.toggle('problem-error', error);
}

function selectDate() {
  savedEntry = entries.find(item => item.date === $('daily-problem-date').value) ?? null;
  $('daily-problem-text').value = savedEntry?.text ?? '';
  dirty = false;
  setStatus(savedEntry ? 'Сохранено' : 'No Data');
}

async function load() {
  const id = ++requestId;
  loading = true;
  $('daily-problem-save').disabled = true;
  try {
    const response = await fetch('/api/daily-problems');
    const result = await response.json();
    if (!response.ok) throw new Error(result.error ?? 'Не удалось прочитать проблему дня.');
    if (id !== requestId) return;
    entries = result.entries;
    currentDay = result.today;
    $('daily-problem-date').max = result.today;
    if (!dirty) {
      $('daily-problem-date').value = $('work-date').value || result.today;
      selectDate();
    }
  } catch (error) {
    if (id !== requestId) return;
    setStatus(error.message, true);
  } finally {
    if (id === requestId) { loading = false; $('daily-problem-save').disabled = saving; }
  }
}

$('daily-problem-date').addEventListener('change', selectDate);
$('daily-problem-text').addEventListener('input', () => { dirty = true; setStatus('Не сохранено'); });
$('daily-problem-help-button').addEventListener('click', () => {
  const open = $('daily-problem-help').hidden;
  $('daily-problem-help').hidden = !open;
  $('daily-problem-help-button').setAttribute('aria-expanded', String(open));
});
$('daily-problem-history').addEventListener('click', () => window.dispatchEvent(new Event('rhythm:show-daily-problems')));
$('daily-problem-form').addEventListener('submit', async event => {
  event.preventDefault();
  if (loading || saving) return;
  const date = $('daily-problem-date').value;
  const text = $('daily-problem-text').value;
  saving = true;
  $('daily-problem-save').disabled = true;
  $('daily-problem-date').disabled = true;
  setStatus('Сохраняю…');
  try {
    const response = await fetch('/api/daily-problems', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ date, text, expectedUpdatedAt: savedEntry?.updatedAt ?? null })
    });
    const result = await response.json();
    if (!response.ok) {
      // Keep the draft while fetching the latest version for a deliberate retry.
      dirty = true;
      await load();
      savedEntry = entries.find(item => item.date === date) ?? null;
      throw new Error(result.error ?? 'Не удалось сохранить проблему.');
    }
    savedEntry = result;
    entries = [...entries.filter(item => item.date !== date), result];
    dirty = $('daily-problem-text').value !== text;
    setStatus(dirty ? 'Есть несохранённые изменения' : 'Сохранено');
    window.dispatchEvent(new Event('rhythm:daily-problem-saved'));
  } catch (error) { setStatus(error.message, true); }
  finally { saving = false; $('daily-problem-save').disabled = loading; $('daily-problem-date').disabled = false; }
});
window.addEventListener('focus', () => { if (!saving) void load(); });
$('data-refresh').addEventListener('click', () => { if (!saving) void load(); });
void load();
