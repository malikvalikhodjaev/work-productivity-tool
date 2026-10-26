const $ = id => document.getElementById(id);
let entries = [];
let savedEntry = null;
let loading = false;
let saving = false;
let dirty = false;
let requestId = 0;
let currentDay = null;
const readonly=Boolean(document.querySelector('meta[name="dashboard-access"][content="viewer"]'));
const focusButton=document.createElement('button');focusButton.id='daily-problem-focus';focusButton.className='button secondary';focusButton.type='button';focusButton.textContent='▶ Фокус';focusButton.disabled=true;
const caseButton=document.createElement('button');caseButton.id='daily-problem-case';caseButton.className='text-button problem-history';caseButton.type='button';caseButton.textContent='Кейс ↗';caseButton.disabled=true;
$('daily-problem-save').after(focusButton,caseButton);
const caseNote=document.createElement('p');caseNote.id='daily-problem-case-note';caseNote.className='problem-status';$('daily-problem-status').after(caseNote);
window.rhythmDailyProblem = { isDirty: () => dirty, isSaving: () => saving };
window.addEventListener('rhythm:work-date-selected', event => {
  if ((dirty || saving) && !event.detail.discard) return;
  $('daily-problem-date').value = event.detail.date; selectDate();
});

function setStatus(text, error = false) {
  $('daily-problem-status').textContent = text;
  $('daily-problem-status').classList.toggle('problem-error', error);
}
function controls(){const active=window.rhythmTimer?.getState()?.active,linked=savedEntry?.caseRef,working=active?.workRef===linked&&linked;focusButton.disabled=readonly||loading||saving||!$('daily-problem-text').value.trim();caseButton.disabled=readonly||loading||saving||!$('daily-problem-text').value.trim();focusButton.textContent=!dirty&&working?(active.status==='paused'?'▶ Продолжить':'Ⅱ Пауза'):'▶ Фокус';caseButton.textContent='Кейс ↗';caseNote.textContent=linked?'Связанный кейс: '+savedEntry.caseTitle:'При сохранении проблема добавится в кейс автоматически. «Фокус» запустит связанный таймер.';}

function selectDate() {
  savedEntry = entries.find(item => item.date === $('daily-problem-date').value) ?? null;
  $('daily-problem-text').value = savedEntry?.text ?? '';
  dirty = false;
  setStatus(savedEntry ? 'Сохранено' : 'Не записано');
  controls();
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
    if (id === requestId) { loading = false; $('daily-problem-save').disabled = saving||readonly;controls(); }
  }
}

$('daily-problem-date').addEventListener('change', selectDate);
$('daily-problem-text').addEventListener('input', () => { dirty = true; setStatus('Не сохранено');controls(); });
$('daily-problem-help-button').addEventListener('click', () => {
  const open = $('daily-problem-help').hidden;
  $('daily-problem-help').hidden = !open;
  $('daily-problem-help-button').setAttribute('aria-expanded', String(open));
});
$('daily-problem-history').addEventListener('click', () => window.dispatchEvent(new Event('rhythm:show-daily-problems')));
async function saveProblem(mode='save') {
  if (loading || saving||readonly) return;
  const date = $('daily-problem-date').value;
  const text = $('daily-problem-text').value;
  saving = true;
  controls();
  $('daily-problem-save').disabled = true;
  $('daily-problem-date').disabled = true;
  setStatus('Сохраняю…');
  try {
    const response = await fetch('/api/daily-problems', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action:mode==='save'?'save':'case',date, text, expectedUpdatedAt: savedEntry?.updatedAt ?? null })
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
    setStatus(dirty ? 'Есть несохранённые изменения' : result.caseCreated?'Сохранено · кейс создан автоматически':'Сохранено · связано с кейсом');
    window.dispatchEvent(new Event('rhythm:daily-problem-saved'));
    window.dispatchEvent(new Event('rhythm:workspace-changed'));
    if(mode!=='save'){
      if(mode==='focus'){
        if(!window.rhythmTimer)throw new Error('Таймер ещё загружается. Кейс сохранён; нажми «Фокус» ещё раз.');
        const started=await window.rhythmTimer.focus({workRef:result.caseRef,title:result.text.slice(0,300),workType:'Диагностика'});
        const active=window.rhythmTimer.getState()?.active;
        setStatus(started?'Проблема в кейсе · таймер запущен':active?.workRef===result.caseRef?'Проблема уже в фокусе':'Кейс сохранён. Сейчас работает другой сеанс или таймер недоступен; проверь «Фокус и время».',!started&&active?.workRef!==result.caseRef);
      }else setStatus(result.caseCreated?'Кейс создан · можно открыть и продолжить размышление':'Связь с кейсом сохранена');
    }
    return true;
  } catch (error) { setStatus(error.message, true);return false; }
  finally { saving = false; $('daily-problem-save').disabled = loading||readonly; $('daily-problem-date').disabled = false;controls(); }
}
$('daily-problem-form').addEventListener('submit',event=>{event.preventDefault();void saveProblem();});
focusButton.addEventListener('click',async()=>{const active=window.rhythmTimer?.getState()?.active;if(!dirty&&savedEntry?.caseRef===active?.workRef&&active?.status==='running'){await window.rhythmTimer.pause(savedEntry.caseRef);controls();}else await saveProblem('focus');});
caseButton.addEventListener('click',async()=>{if((dirty||!savedEntry?.caseRef)&&!await saveProblem('case'))return;if(savedEntry?.caseRef)window.dispatchEvent(new CustomEvent('rhythm:open-case',{detail:{caseId:savedEntry.caseRef.slice(5)}}));});
window.addEventListener('rhythm:timer-state',controls);
window.addEventListener('rhythm:workspace-changed',()=>{if(!saving)void load();});
window.addEventListener('focus', () => { if (!saving) void load(); });
$('data-refresh').addEventListener('click', () => { if (!saving) void load(); });
void load();
