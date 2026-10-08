const $ = id => document.getElementById(id);
const escape = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
let portfolio = null;
let selectedProject = null;
let editedProject = null;
let editedAlpha = null;
let editedAlphaRevision = 0;
let noticeTimer;
let dataWeek = null;
let dataTables = null;
let activeDataTable = 'timeEntries';
let dataRequestId = 0;
let currentView = null;
const projectStatus = { active: 'Активен', paused: 'На паузе', closed: 'Закрыт' };
const phaseTitle = { pre_operation: 'До эксплуатации', operation: 'В эксплуатации' };
const today = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Tashkent', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
const selected = () => portfolio?.projects.find(project => project.id === selectedProject);

async function request(action, input) {
  const knownProjects = new Set(portfolio?.projects.map(project => project.id) ?? []);
  const response = await fetch('/api/portfolio', action ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action, input }) } : undefined);
  const result = await response.json();
  if (!response.ok) throw new Error(result.error ?? 'Не удалось сохранить проекты.');
  portfolio = result;
  if (action === 'createProject') selectedProject = portfolio.projects.find(project => !knownProjects.has(project.id))?.id ?? selectedProject;
  if (!portfolio.projects.some(project => project.id === selectedProject)) selectedProject = portfolio.projects.find(project => project.status === 'active')?.id ?? portfolio.projects[0]?.id ?? null;
  render();
  if (action) window.dispatchEvent(new Event('rhythm:portfolio-saved'));
  return result;
}

async function loadPortfolio() {
  try { await request(); $('portfolio-error').hidden = true; }
  catch (error) { $('portfolio-error-text').textContent = error.message; $('portfolio-error').hidden = false; }
}

function notice(message) {
  clearTimeout(noticeTimer);
  $('toast').textContent = message;
  $('toast').hidden = false;
  noticeTimer = setTimeout(() => { $('toast').hidden = true; }, 3500);
}

function setView(view) {
  if (view === 'financial') { view = 'week'; history.replaceState(null, '', '#week'); $('financial-panel').open = true; }
  if (!['week', 'projects', 'work', 'data'].includes(view)) view = 'week';
  const changed = currentView !== view;
  currentView = view;
  const wasData = !$('data-panel').hidden;
  const projects = view === 'projects';
  $('week-panel').hidden = view !== 'week';
  $('projects-panel').hidden = !projects;
  $('work-panel').hidden = view !== 'work';
  $('data-panel').hidden = view !== 'data';
  $('period-toolbar').hidden = view !== 'week';
  $('week-actions').hidden = view !== 'week';
  $('project-actions').hidden = !projects;
  const title = view === 'week' ? 'Показатели' : projects ? 'Проекты' : view === 'work' ? 'Работа' : 'Данные';
  $('page-title').innerHTML = `${title}<span class="title-dot">.</span>`;
  for (const [id, isSelected] of [['week-tab', view === 'week'], ['projects-tab', projects], ['work-tab', view === 'work'], ['data-tab', view === 'data']]) {
    $(id).setAttribute('aria-selected', String(isSelected));
    $(id).tabIndex = isSelected ? 0 : -1;
  }
  document.title = `Ритм — ${title.toLowerCase()}`;
  if (view === 'data' && !wasData) void loadData();
  if (projects) syncModeler();
  if (changed && view === 'work') window.dispatchEvent(new Event('rhythm:work-opened'));
  if (changed) window.scrollTo(0, 0);
}

function chooseView(view) { window.location.hash = view; setView(view); }
$('week-tab').addEventListener('click', () => chooseView('week'));
$('projects-tab').addEventListener('click', () => chooseView('projects'));
$('work-tab').addEventListener('click', () => chooseView('work'));
window.addEventListener('rhythm:show-work', () => chooseView('work'));
$('data-tab').addEventListener('click', () => chooseView('data'));
window.addEventListener('rhythm:show-assessments', () => { activeDataTable = 'assessments'; chooseView('data'); });
window.addEventListener('rhythm:show-daily-problems', () => { activeDataTable = 'dailyProblems'; chooseView('data'); renderData(); });
window.addEventListener('rhythm:show-daily-results', () => { activeDataTable = 'dailyResults'; chooseView('data'); renderData(); });
window.addEventListener('rhythm:show-sources', () => { activeDataTable = 'sources'; chooseView('data'); renderData(); });
for (const id of ['week-tab', 'projects-tab', 'work-tab', 'data-tab']) $(id).addEventListener('keydown', event => {
  if (['ArrowRight', 'ArrowLeft', 'ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
    event.preventDefault();
    const views = ['week', 'projects', 'work', 'data'];
    const current = views.indexOf(id.replace('-tab', ''));
    const view = event.key === 'Home' ? 'week' : event.key === 'End' ? 'data' : views[(current + (['ArrowRight', 'ArrowDown'].includes(event.key) ? 1 : views.length - 1)) % views.length];
    chooseView(view); $(`${view}-tab`).focus();
  }
});
window.addEventListener('hashchange', () => setView(window.location.hash.slice(1)));

function alphaCard(alpha, depth = 0) {
  const state = portfolio.states.find(item => item.id === alpha.state);
  const children = portfolio.alphas.filter(item => item.parentId === alpha.id);
  const parent = portfolio.alphas.find(item => item.id === alpha.parentId);
  const body = `<article class="alpha-card">
    <div class="alpha-card-top"><span class="alpha-type">${escape(alpha.typeName)}</span><span class="status-pill ${alpha.assessment.ok ? 'confirmed' : alpha.state === 'empty' ? 'empty' : 'warning'}">${state.title}</span></div>
    ${parent ? `<p class="alpha-parent-label">Подальфа: ${escape(parent.uniqueName || parent.typeName)}</p>` : ''}
    <h3>${escape(alpha.uniqueName || 'No Data')}</h3>
    <p class="alpha-description">${escape(alpha.description || 'No Data')}</p>
    ${alpha.stateLabel ? `<p class="alpha-state-label">По шаблону: ${escape(alpha.stateLabel)}</p>` : ''}
    <div class="alpha-checks"><span class="${alpha.filledDate ? 'has-value' : ''}">${alpha.filledDate ? 'Слот заполнен' : 'Слот не заполнен'}</span><span class="${alpha.criteria ? 'has-value' : ''}">${alpha.criteria ? 'Критерий задан' : 'Нет критерия'}</span><span class="${alpha.evidence ? 'has-value' : ''}">${alpha.evidence ? 'Есть подтверждение' : 'Нет подтверждения'}</span></div>
    <p class="alpha-date">Дата заполнения: <strong>${alpha.filledDate ? escape(alpha.filledDate) : 'No Data'}</strong></p>
    ${alpha.nextStep ? `<p class="alpha-step">Далее: ${escape(alpha.nextStep)}</p>` : ''}
    ${!alpha.assessment.ok && children.length ? '<p class="zone-issues">Состояния подальф учитываются отдельно.</p>' : ''}
    <div data-impact-ref="alpha:${alpha.id}"></div><div class="alpha-card-footer"><button class="text-button" data-alpha-edit="${alpha.id}">Заполнить / изменить</button><button class="text-button" data-alpha-child="${alpha.id}">＋ Подальфа</button><button class="text-button" data-alpha-task="${alpha.id}">＋ Задача</button></div>
  </article>`;
  return `${depth ? '<div class="alpha-child">' : ''}${body}${children.map(child => alphaCard(child, depth + 1)).join('')}${depth ? '</div>' : ''}`;
}

async function syncModeler() {
  const project = selected();
  $('project-modeler').hidden = !project;
  if (!project) return;
  const frame = $('alpha-modeler-frame');
  $('modeler-project-label').textContent = project.name;
  $('modeler-fullscreen').href = '/alphas?project=' + encodeURIComponent(project.id);
  if (currentView !== 'projects') return;
  if (!frame.getAttribute('src')) frame.src = '/alphas?embedded=1&project=' + encodeURIComponent(project.id);
  else {
    try {
      const bridge = frame.contentWindow.rhythmAlphaModeler;
      if (await bridge?.selectProject(project.id) === false && bridge.currentProjectId && selectedProject === project.id) {
        selectedProject = bridge.currentProjectId; render();
      }
    } catch (error) { notice(error.message); }
  }
}

function render() {
  syncModeler();
  $('new-project').disabled = false;
  $('active-projects').textContent = portfolio.summary.activeProjects;
  $('before-operation-tasks').textContent = portfolio.summary.beforeOperationTasks;
  const taskCount = portfolio.summary.beforeOperationTasks;
  const taskWord = taskCount % 100 >= 11 && taskCount % 100 <= 14 ? 'задач' : taskCount % 10 === 1 ? 'задача' : taskCount % 10 >= 2 && taskCount % 10 <= 4 ? 'задачи' : 'задач';
  $('before-operation-tasks').nextElementSibling.textContent = ` ${taskWord}`;
  $('all-open-tasks').textContent = `Всего открытых задач: ${portfolio.summary.openTasks}`;
  $('gap-zones').textContent = portfolio.summary.gapZones;
  $('new-alpha').disabled = !selected();
  $('new-task').disabled = !selected();
  $('project-list').innerHTML = portfolio.projects.length ? portfolio.projects.map(project => `<button class="project-choice ${project.id === selectedProject ? 'selected' : ''}" data-project="${project.id}" aria-pressed="${project.id === selectedProject}"><span class="project-choice-title">${escape(project.name)}<span class="status-pill ${project.status === 'active' ? 'active' : ''}">${projectStatus[project.status]}</span></span><span class="project-choice-meta"><span>Зоны: ${project.summary.coveredZones}/${project.summary.totalZones}</span><span>Слоты: ${project.summary.filled}/${project.summary.slots}</span><span>До эксплуатации: ${project.summary.beforeOperationTasks}</span></span></button>`).join('') : '<div class="project-empty">Создай первый проект и выбери зоны, которые хочешь отслеживать.</div>';
  const project = selected();
  if (!project) { $('project-detail').innerHTML = ''; return; }
  const alphas = portfolio.alphas.filter(alpha => alpha.projectId === project.id && !alpha.parentId);
  const tasks = portfolio.tasks.filter(task => task.projectId === project.id).sort((a, b) => Number(a.done) - Number(b.done));
  $('project-detail').innerHTML = `<section aria-label="Проект ${escape(project.name)}"><div class="project-title-row"><div><h2>${escape(project.name)}</h2><div class="project-title-meta"><span>${phaseTitle[project.phase]}</span><span>·</span><span>${projectStatus[project.status]}</span><span>·</span><span>Зон подтверждено: ${project.summary.coveredZones}/${project.summary.totalZones}</span></div></div><div class="project-title-actions"><button id="edit-current-project" class="text-button">Настройки проекта</button><button id="add-project-zone" class="text-button">＋ Зона</button></div></div>${project.phase === 'operation' && project.summary.beforeOperationTasks ? `<p class="task-warning">Проект в эксплуатации, но задач до запуска ещё открыто: ${project.summary.beforeOperationTasks}.</p>` : ''}<div data-impact-ref="project:${project.id}"></div><div class="zone-grid">${project.zones.map(zone => `<article class="zone-card ${zone.covered ? 'covered' : ''}"><div class="zone-card-top"><h3>${escape(zone.title)}</h3><span class="status-pill ${zone.covered ? 'confirmed' : 'warning'}">${zone.covered ? 'Подтверждено' : 'Есть пробел'}</span></div><p>${escape(zone.hint || 'Заполни альфы этой зоны, критерии и подтверждения их состояний.')}</p><div class="zone-issues">${zone.covered ? 'Все альфы и подальфы зоны подтверждены.' : escape(zone.issues.join(' · '))}</div>${zone.slotCount ? '' : `<button class="text-button" data-zone-slot="${zone.id}">Создать слот альфы</button>`}</article>`).join('')}</div><div class="section-heading alpha-section-heading"><h2>Слоты альф <span class="count-badge">${project.summary.slots}</span></h2><span class="slot-count">Заполнено: ${project.summary.filled}/${project.summary.slots} · готовность оценивается отдельно</span></div><div class="alpha-list">${alphas.length ? alphas.map(alpha => `<div class="alpha-tree">${alphaCard(alpha)}</div>`).join('') : '<div class="project-empty">Слотов пока нет. Добавь типовое имя альфы и конкретный объект проекта.</div>'}</div><section class="project-tasks" aria-label="Задачи проекта"><div class="section-heading"><h2>Задачи до эксплуатации <span class="count-badge">${project.summary.beforeOperationTasks}</span></h2><button id="detail-new-task" class="text-button">＋ Задача</button></div>${tasks.length ? `<div class="task-list">${tasks.map(task => {
    const alpha = portfolio.alphas.find(item => item.id === task.alphaId);
    return `<div class="project-task-row"><button class="task-toggle" data-task-toggle="${task.id}" aria-pressed="${task.done}" aria-label="${task.done ? 'Открыть снова' : 'Закрыть задачу'}: ${escape(task.title)}">${task.done ? '✓' : ''}</button><div class="task-text ${task.done ? 'done' : ''}"><strong>${escape(task.title)}</strong><div data-impact-ref="task:${task.id}"></div><div class="task-meta">${task.done ? 'Закрыта' : 'Открыта'} · ${task.beforeOperation ? 'До эксплуатации' : 'Текущая задача'}${alpha ? ` · ${escape(alpha.uniqueName || alpha.typeName)}` : ''}</div></div></div>`;
  }).join('')}</div>` : '<div class="project-empty">Открытых задач пока нет. Пробел в зоне можно превратить в задачу кнопкой на карточке альфы.</div>'}</section></section>`;
  window.dispatchEvent(new Event('rhythm:portfolio-rendered'));
}

function tableValue(value) { return value === null || value === undefined || value === '' ? 'No Data' : String(value); }
function countLabel(count, one, few, many) { return `${count} ${count % 100 >= 11 && count % 100 <= 14 ? many : count % 10 === 1 ? one : count % 10 >= 2 && count % 10 <= 4 ? few : many}`; }

function makeDataTables(week, snapshot, imported, ratings, dailyProblems, dailyResults, alphaBackup, storedEntries, references) {
  const projects = new Map(snapshot.projects.map(project => [project.id, project]));
  const alphas = new Map(snapshot.alphas.map(alpha => [alpha.id, alpha]));
  const metrics = new Map(week.metrics.map(metric => [metric.id, metric]));
  return {
    sources: {
      title: 'Источники и мысли', note: `${countLabel(references.entries.length, 'запись', 'записи', 'записей')} · data/references.json · исходные формулировки и заметки`,
      columns: ['ID', 'Группа', 'Название', 'Ссылка', 'Вложение', 'Кто / источник', 'Исходная запись', 'Моя заметка', 'Добавлено', 'Обновлено', 'Правок'],
      rows: references.entries.map(item => [item.id, item.group, item.title, item.url, item.attachment ? `/api/references/${encodeURIComponent(item.id)}/attachment` : null, item.attribution, item.originalText, item.note, item.createdAt, item.updatedAt, item.revisions?.length ?? 0])
    },
    timeEntries: {
      title: 'Все записи времени и количества', note: `${storedEntries.entries.length} строк · вся история · изменение хранилища: ${tableValue(storedEntries.updatedAt)}`,
      columns: ['ID', 'Дата', 'Код норматива', 'Назначение', 'Количество', 'Что сделано', 'Характер работы', 'Связь', 'Источник', 'ID источника', 'Создано', 'История разбора'],
      rows: storedEntries.entries.map(e => [e.id, e.date, e.metricId, e.allocation, e.amount, e.title, e.workType, e.workRef, e.source, e.externalId, e.createdAt, e.classificationHistory?.length ? JSON.stringify(e.classificationHistory) : null])
    },
    norms: {
      title: 'Недельные нормативы', note: week.week + ' — ' + week.end + ' · источник: data/dashboard.json → plans',
      columns: ['Код', 'Норматив', 'Цель', 'Единица', 'Факт', 'Записей', 'Прогресс, %'],
      rows: week.metrics.map(m => [m.id, m.title, m.target, m.unit === 'hours' ? 'ч' : 'шт.', m.recordCount ? m.actual : null, m.recordCount, m.recordCount && m.target ? m.percent : null])
    },
    alphaHistory: {
      title: 'История альф', note: 'Содержательные сохранения · источник: data/dashboard.json → portfolio.history',
      columns: ['ID', 'ID альфы', 'Дата', 'Действие', 'Объект', 'Запись', 'Факт', 'Критерий', 'Следующий ход'],
      rows: alphaBackup.history.map(h => [h.id, h.alphaId, h.at, h.action, h.snapshot.uniqueName, h.snapshot.description, h.snapshot.evidence, h.snapshot.criteria, h.snapshot.nextStep])
    },
    entries: {
      title: 'Записи недели',
      note: `${week.week} — ${week.end} · ${countLabel(week.entries.length, 'запись', 'записи', 'записей')}`,
      columns: ['Дата', 'Направление', 'Что сделано', 'Количество', 'Источник'],
      rows: week.entries.map(entry => {
        const metric = metrics.get(entry.metricId) ?? { title: entry.allocation === 'outside' ? 'Вне нормативов' : 'Не разобрано', unit: 'hours' };
        return [entry.date, metric?.title, entry.title, `${entry.amount} ${metric?.unit === 'hours' ? 'ч' : 'шт.'}`, entry.source === 'manual' ? 'Вручную' : entry.source];
      })
    },
    dailyResults: {
      title: 'Главная работа и результаты дня',
      note: `${countLabel(dailyResults.entries.length, 'запись', 'записи', 'записей')} · вся история по датам · data/daily-results.csv`,
      columns: ['Дата', 'Главное', 'Состояние', 'Прогресс, %', 'Связь', 'Почему важно', 'Следующий ход', 'Окно фокуса · план', 'Подтверждение', 'Обновлено', 'Правок'],
      rows: dailyResults.entries.map(item => [item.date, item.text, ({planned:'Выбрано',in_progress:'В работе',blocked:'Есть препятствие',ready:'Готово'})[item.status], item.progress, item.workRef, item.whyImportant, item.nextStep, item.focusWindow, item.evidence, new Date(item.updatedAt).toLocaleString('ru-RU', { timeZone: 'Asia/Tashkent' }), item.revisions.length])
    },
    dailyProblems: {
      title: 'Главная проблема дня',
      note: `${countLabel(dailyProblems.entries.length, 'запись', 'записи', 'записей')} · вся история по датам · правки сохраняются в data/daily-problems.json`,
      columns: ['Дата', 'Проблема', 'Обновлено', 'Правок'],
      rows: dailyProblems.entries.map(item => [item.date, item.text, new Date(item.updatedAt).toLocaleString('ru-RU', { timeZone: 'Asia/Tashkent' }), item.revisions.length])
    },
    assessments: {
      title: 'Самооценки',
      note: `${countLabel(ratings.observations.length, 'оценка', 'оценки', 'оценок')} · локальная таблица data/indicator-ratings.csv · шкала от 0 до 10`,
      columns: ['Дата', 'Показатель', 'Оценка', 'Заметка'],
      rows: ratings.observations.map(item => [item.date, ratings.indicators.find(indicator => indicator.id === item.indicatorId)?.title, `${item.score}/10`, item.note])
    },
    projects: {
      title: 'Проекты',
      note: `${countLabel(snapshot.projects.length, 'проект', 'проекта', 'проектов')} · все статусы`,
      columns: ['Проект', 'Статус', 'Этап', 'Зоны', 'Слоты альф', 'Открыто до эксплуатации'],
      rows: snapshot.projects.map(project => [project.name, projectStatus[project.status], phaseTitle[project.phase], `${project.summary.coveredZones}/${project.summary.totalZones}`, `${project.summary.filled}/${project.summary.slots}`, project.summary.beforeOperationTasks])
    },
    alphas: {
      title: 'Альфы',
      note: `${countLabel(snapshot.alphas.length, 'слот', 'слота', 'слотов')} · включая подальфы`,
      columns: ['ID', 'Проект', 'Зона', 'Родитель', 'Типовое имя', 'Уникальное имя', 'Запись', 'Факт', 'Критерий', 'Состояние', 'Состояние шаблона', 'Дата заполнения', 'Следующий шаг', 'Вернуться', 'Адаптированная альфа', 'Область', 'Почему важен', 'Источник', 'Адаптация', 'Время системы', 'Статус внимания', 'Версия', 'Изменено'],
      rows: snapshot.alphas.map(alpha => {
        const project = projects.get(alpha.projectId);
        const zone = project?.zones.find(item => item.id === alpha.zoneId);
        return [alpha.id, project?.name, zone?.title, alpha.parentId, alpha.typeName, alpha.uniqueName, alpha.description, alpha.evidence, alpha.criteria, snapshot.states.find(item => item.id === alpha.state)?.title, alpha.stateLabel, alpha.filledDate, alpha.nextStep, alpha.reviewDate, alpha.adaptedAlpha, alpha.area, alpha.whyImportant, alpha.source, alpha.metaAdaptation, alpha.systemTime, alpha.attention, alpha.revision, alpha.updatedAt];
      })
    },
    tasks: {
      title: 'Задачи',
      note: `${countLabel(snapshot.tasks.length, 'задача', 'задачи', 'задач')} · все проекты`,
      columns: ['Проект', 'Задача', 'Альфа', 'До эксплуатации', 'Статус'],
      rows: [...snapshot.tasks].sort((a, b) => Number(a.done) - Number(b.done)).map(task => [projects.get(task.projectId)?.name, task.title, alphas.get(task.alphaId)?.uniqueName || alphas.get(task.alphaId)?.typeName, task.beforeOperation ? 'Да' : 'Нет', task.done ? 'Закрыта' : 'Открыта'])
    },
    work: {
      title: 'Работы Coda',
      note: imported.snapshot.available ? `${countLabel(imported.snapshot.work.length, 'строка', 'строки', 'строк')} · снимок доски на ${tableValue(imported.snapshot.capturedAt)} · не все строки являются активными задачами` : 'No Data · снимок Coda не загружен',
      sourceUrl: imported.snapshot.sources.work,
      columns: ['Работа', 'Стадия', 'Проект', 'Тип работы', 'Цели', 'Срок', 'Чек-бокс'],
      rows: imported.snapshot.work.map(item => [item.title, item.stage, item.projects.join(', '), item.workType, item.goals.join(', '), item.deadline, item.done ? 'Отмечено' : 'Не отмечено'])
    },
    goals: {
      title: 'Цели Coda',
      note: imported.snapshot.available ? `${countLabel(imported.snapshot.goals.length, 'цель', 'цели', 'целей')} · снимок на ${tableValue(imported.snapshot.capturedAt)} · статус «Записана» не означает достижение` : 'No Data · снимок Coda не загружен',
      sourceUrl: imported.snapshot.sources.goals,
      columns: ['Цель', 'Статус', 'Область', 'Как измеряем', 'Выполнение', 'Срок'],
      rows: imported.snapshot.goals.map(item => [item.title, item.status, item.area, item.measurement, item.completion, item.deadline])
    },
    issues: {
      title: 'Issues Coda',
      note: imported.snapshot.available ? `${countLabel(imported.snapshot.issues.length, 'заполненная строка', 'заполненные строки', 'заполненных строк')} · пустые строки источника исключены` : 'No Data · снимок Coda не загружен',
      sourceUrl: imported.snapshot.sources.issues,
      columns: ['Задача / вопрос', 'Статус', 'Заметка'],
      rows: imported.snapshot.issues.map(item => [item.title, item.status, item.note])
    },
    reference: {
      title: 'Справочник альф',
      note: imported.reference.available ? `${countLabel(imported.reference.rows.length, 'строка', 'строки', 'строк')} · исходный шаблон, не прогресс проектов` : 'No Data · справочник не загружен',
      sourceUrl: imported.reference.sources.catalog,
      columns: ['Уровень', 'Область', 'Альфа', 'Состояние', 'Контрольный вопрос', 'Статус в шаблоне'],
      rows: imported.reference.rows.map(item => [item.level, item.area, item.alpha, item.state, item.question, item.checkStatus])
    },
    roles: {
      title: 'Роли и практики',
      note: imported.reference.available ? `${countLabel(imported.reference.roles.length, 'роль', 'роли', 'ролей')} · подсказки из «Менеджмент и инженерка»` : 'No Data · справочник не загружен',
      sourceUrl: imported.reference.sources.management,
      columns: ['Роль', 'Практика', 'Область'],
      rows: imported.reference.roles.map(item => [item.role, item.practice, item.area])
    },
    mistakes: {
      title: 'Типовые ошибки',
      note: imported.reference.available ? `${countLabel(imported.reference.mistakes.length, 'ошибка', 'ошибки', 'ошибок')} · подсказки из «Менеджмент и инженерка»` : 'No Data · справочник не загружен',
      sourceUrl: imported.reference.sources.management,
      columns: ['Ошибка', 'Почему важно'],
      rows: imported.reference.mistakes.map(item => [item.mistake, item.reason])
    },
    actions: {
      title: 'Рабочие ходы',
      note: imported.reference.available ? `${countLabel(imported.reference.actions.length, 'действие', 'действия', 'действий')} · подсказки из «Менеджмент и инженерка»` : 'No Data · справочник не загружен',
      sourceUrl: imported.reference.sources.management,
      columns: ['Что делать', 'Почему важно'],
      rows: imported.reference.actions.map(item => [item.action, item.reason])
    }
  };
}

function renderData() {
  if (!dataTables) return;
  for (const [key, id] of [['entries', 'data-entries-count'], ['projects', 'data-projects-count'], ['alphas', 'data-alphas-count'], ['tasks', 'data-tasks-count']]) $(id).textContent = dataTables[key].rows.length;
  const table = dataTables[activeDataTable];
  if (!table) return;
  const localSources = { timeEntries: 'data/dashboard.json → entries', entries: 'data/dashboard.json → entries', projects: 'data/dashboard.json → portfolio.projects', alphas: 'data/dashboard.json → portfolio.alphas', tasks: 'data/dashboard.json → portfolio.tasks', dailyResults: 'data/daily-results.json', dailyProblems: 'data/daily-problems.json', assessments: 'data/indicators.json' };
  $('data-table-title').textContent = table.title;
  $('data-table-note').textContent = table.note + (localSources[activeDataTable] ? ' · источник: ' + localSources[activeDataTable] : '');
  $('data-table-caption').textContent = table.title;
  $('data-source').hidden = !table.sourceUrl;
  $('data-source').innerHTML = table.sourceUrl ? `Источник: <a href="${escape(table.sourceUrl)}" target="_blank" rel="noopener noreferrer">открыть в Coda ↗</a>` : '';
  $('data-table-head').innerHTML = `<tr>${table.columns.map(column => `<th scope="col">${escape(column)}</th>`).join('')}</tr>`;
  $('data-table-body').innerHTML = table.rows.length ? table.rows.map(row => `<tr>${row.map((value, index) => `<td>${activeDataTable === 'sources' && value && ((index === 3 && /^https?:\/\//i.test(value)) || (index === 4 && /^\/api\/references\/[a-z0-9-]+\/attachment$/.test(value))) ? `<a href="${escape(value)}" target="_blank" rel="noopener noreferrer">${index === 4 ? 'Скриншот ↗' : escape(value)}</a>` : escape(tableValue(value))}</td>`).join('')}</tr>`).join('') : `<tr><td class="data-empty" colspan="${table.columns.length}">No Data</td></tr>`;
  $('data-download').disabled = table.rows.length === 0;
  document.querySelectorAll('[data-table]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.table === activeDataTable)));
}

async function loadData() {
  const currentRequest = ++dataRequestId;
  $('data-refresh').disabled = true;
  $('data-table-note').textContent = 'Обновляю таблицы…';
  $('data-error').hidden = true;
  try {
    const [weekResponse, portfolioResponse, importedResponse, ratingsResponse, problemsResponse, resultsResponse, alphaResponse, entriesResponse, referencesResponse] = await Promise.all([
      fetch(`/api/dashboard${dataWeek ? `?week=${encodeURIComponent(dataWeek)}` : ''}`),
      fetch('/api/portfolio'),
      fetch('/api/imported-data'),
      fetch('/api/indicator-ratings'),
      fetch('/api/daily-problems'),
      fetch('/api/daily-results'),
      fetch('/api/alphas/export'),
      fetch('/api/time-entries'),
      fetch('/api/references')
    ]);
    if (!weekResponse.ok || !portfolioResponse.ok || !importedResponse.ok || !ratingsResponse.ok || !problemsResponse.ok || !resultsResponse.ok || !alphaResponse.ok || !entriesResponse.ok || !referencesResponse.ok) throw new Error('Не удалось прочитать локальные данные.');
    const [week, snapshot, imported, ratings, dailyProblems, dailyResults, alphaBackup, storedEntries, references] = await Promise.all([weekResponse.json(), portfolioResponse.json(), importedResponse.json(), ratingsResponse.json(), problemsResponse.json(), resultsResponse.json(), alphaResponse.json(), entriesResponse.json(), referencesResponse.json()]);
    if (currentRequest !== dataRequestId) return;
    dataTables = makeDataTables(week, snapshot, imported, ratings, dailyProblems, dailyResults, alphaBackup, storedEntries, references);
    for (const key of ['work', 'goals', 'issues']) $('import-' + key + '-count').textContent = imported.snapshot.available ? imported.snapshot[key].length : 'No Data';
    $('import-captured-at').textContent = tableValue(imported.snapshot.capturedAt);
    $('reference-summary-text').textContent = imported.reference.available
      ? `${imported.reference.rows.length} строк справочника · ${imported.reference.roles.length} ролей · ${imported.reference.mistakes.length} ошибок · ${imported.reference.actions.length} рабочих ходов. Подсказки для адаптации под проект.`
      : 'No Data · пакет шаблонов ещё не загружен.';
    $('reference-links').innerHTML = [['catalog', 'Шаблон объектов ↗'], ['management', 'Менеджмент и инженерка ↗']]
      .filter(([key]) => /^https?:\/\//i.test(imported.reference.sources[key] ?? ''))
      .map(([key, title]) => `<a href="${escape(imported.reference.sources[key])}" target="_blank" rel="noopener noreferrer">${title}</a>`).join('');
    $('reference-guide-content').innerHTML = imported.reference.available
      ? `<p>Создай экземпляр шаблона для конкретного проекта. Заполняй только нужные поля и возвращайся к проверке состояния:</p><ol>${imported.reference.guidance.map(item => `<li>${escape(item)}</li>`).join('')}</ol><p><strong>Поля карточки:</strong> ${imported.reference.objectFields.map(escape).join(' · ')}</p>`
      : '<p>No Data · подсказки появятся после загрузки пакета шаблонов.</p>';
    renderData();
  } catch (error) {
    if (currentRequest !== dataRequestId) return;
    dataTables = null;
    $('data-error').textContent = error.message;
    $('data-error').hidden = false;
    $('data-table-title').textContent = 'Таблица недоступна';
    $('data-table-note').textContent = 'No Data';
    for (const id of ['data-entries-count', 'data-projects-count', 'data-alphas-count', 'data-tasks-count', 'import-work-count', 'import-goals-count', 'import-issues-count']) $(id).textContent = 'No Data';
    $('data-source').hidden = true;
    $('data-table-head').innerHTML = '<tr><th scope="col">Данные</th></tr>';
    $('data-table-body').innerHTML = '<tr><td class="data-empty">No Data</td></tr>';
    $('data-download').disabled = true;
  } finally { if (currentRequest === dataRequestId) $('data-refresh').disabled = false; }
}

function csvCell(value) {
  let content = tableValue(value);
  if (/^[\s\u0000-\u001f]*[=+\-@]/.test(content)) content = `'${content}`;
  return `"${content.replaceAll('"', '""')}"`;
}

function downloadData() {
  const table = dataTables?.[activeDataTable];
  if (!table?.rows.length) return;
  const lines = [table.columns, ...table.rows].map(row => row.map(csvCell).join(';')).join('\r\n');
  const url = URL.createObjectURL(new Blob([`\uFEFF${lines}\r\n`], { type: 'text/csv;charset=utf-8' }));
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `rhythm-${activeDataTable}${activeDataTable === 'entries' && dataWeek ? `-${dataWeek}` : ''}.csv`;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function openProject(id = null) {
  editedProject = id;
  const project = portfolio.projects.find(item => item.id === id);
  $('project-form').reset();
  $('project-form-title').textContent = project ? 'Настройки проекта' : 'Новый проект';
  $('project-name').value = project?.name ?? '';
  $('project-status').value = project?.status ?? 'active';
  $('project-phase').value = project?.phase ?? 'pre_operation';
  const zones = [...(project?.zones ?? []), ...portfolio.defaultZones.filter(zone => !project?.zones.some(item => item.id === zone.id))];
  $('project-zone-options').innerHTML = zones.map(zone => `<label class="checkbox-label"><input type="checkbox" name="zone" value="${zone.id}" ${!project || project.zones.some(item => item.id === zone.id) ? 'checked' : ''}>${escape(zone.title)}</label>`).join('');
  $('project-form-error').hidden = true;
  $('project-dialog').showModal();
}

function openZone() {
  $('zone-form').reset(); $('zone-form-error').hidden = true; $('zone-dialog').showModal();
}

function openAlpha(id = null, parentId = null, zoneId = null) {
  editedAlpha = id;
  editedAlphaRevision = portfolio.alphas.find(item => item.id === id)?.revision ?? 0;
  const project = selected();
  const alpha = portfolio.alphas.find(item => item.id === id);
  $('alpha-form').reset();
  $('alpha-form-error').hidden = true;
  $('alpha-form-title').textContent = alpha ? 'Изменить альфу' : parentId ? 'Новая подальфа' : 'Новый слот альфы';
  $('alpha-project-label').textContent = project.name;
  $('alpha-zone').innerHTML = project.zones.map(zone => `<option value="${zone.id}">${escape(zone.title)}</option>`).join('');
  $('alpha-zone').value = alpha?.zoneId ?? zoneId ?? project.zones[0].id;
  const descendants = new Set();
  function childrenOf(parent) { for (const child of portfolio.alphas.filter(item => item.parentId === parent)) { descendants.add(child.id); childrenOf(child.id); } }
  if (alpha) childrenOf(alpha.id);
  const parents = portfolio.alphas.filter(item => item.projectId === project.id && item.id !== id && !descendants.has(item.id));
  $('alpha-parent').innerHTML = '<option value="">Самостоятельная альфа</option>' + parents.map(item => `<option value="${item.id}">${escape(item.uniqueName || item.typeName)}</option>`).join('');
  $('alpha-parent').value = alpha?.parentId ?? parentId ?? '';
  $('alpha-type').value = alpha?.typeName ?? (parentId ? '' : project.zones.find(zone => zone.id === $('alpha-zone').value)?.typeName ?? '');
  $('alpha-name').value = alpha?.uniqueName ?? '';
  $('alpha-description').value = alpha?.description ?? '';
  $('alpha-state').innerHTML = portfolio.states.map(state => `<option value="${state.id}">${state.title}</option>`).join('');
  $('alpha-state').value = alpha?.state ?? 'empty';
  for (const [id, key] of [['alpha-state-label', 'stateLabel'], ['alpha-criteria', 'criteria'], ['alpha-evidence', 'evidence'], ['alpha-next-step', 'nextStep']]) $(id).value = alpha?.[key] ?? '';
  $('alpha-filled').checked = Boolean(alpha?.filledDate);
  $('alpha-filled-date').value = alpha?.filledDate ?? '';
  syncAlphaParent(); syncFilled();
  $('alpha-dialog').showModal();
}

function syncAlphaParent() {
  const parent = portfolio.alphas.find(alpha => alpha.id === $('alpha-parent').value);
  $('alpha-zone').disabled = Boolean(parent);
  if (parent) $('alpha-zone').value = parent.zoneId;
}
function syncFilled() { $('alpha-filled-date').disabled = !$('alpha-filled').checked; $('alpha-filled-date').required = $('alpha-filled').checked; if ($('alpha-filled').checked && !$('alpha-filled-date').value) $('alpha-filled-date').value = today(); }

function openTask(alphaId = null) {
  const project = selected();
  $('task-form').reset(); $('task-form-error').hidden = true;
  $('task-project-label').textContent = project.name;
  const alphas = portfolio.alphas.filter(alpha => alpha.projectId === project.id);
  $('task-alpha').innerHTML = '<option value="">Без привязки к альфе</option>' + alphas.map(alpha => `<option value="${alpha.id}">${escape(alpha.uniqueName || alpha.typeName)}</option>`).join('');
  $('task-alpha').value = alphaId ?? '';
  $('task-title').value = alphas.find(alpha => alpha.id === alphaId)?.nextStep ?? '';
  $('task-dialog').showModal();
}

async function submit(event, errorId, action, input, dialog, message) {
  event.preventDefault();
  const button = event.currentTarget.querySelector('button[type=submit]');
  button.disabled = true; $(errorId).hidden = true;
  try {
    await request(action, input);
    $(dialog).close(); notice(message);
  } catch (error) { $(errorId).textContent = error.message; $(errorId).hidden = false; }
  finally { button.disabled = false; }
}

$('new-project').addEventListener('click', () => { if (portfolio) openProject(); });
$('new-alpha').addEventListener('click', () => openAlpha());
$('new-task').addEventListener('click', () => openTask());
$('data-refresh').addEventListener('click', () => void loadData());
$('data-download').addEventListener('click', downloadData);
$('data-table-switches').addEventListener('click', event => {
  const button = event.target.closest('[data-table]');
  if (!button) return;
  activeDataTable = button.dataset.table;
  renderData();
});
window.addEventListener('rhythm:week-loaded', event => {
  dataWeek = event.detail.week;
  if (!$('data-panel').hidden) void loadData();
});
window.addEventListener('rhythm:portfolio-saved', () => {
  if (!$('data-panel').hidden) void loadData();
  const refresh = $('alpha-modeler-frame').contentWindow?.rhythmAlphaModeler?.refresh;
  if (refresh) void refresh().catch(error => notice(error.message));
});
window.addEventListener('rhythm:daily-problem-saved', () => { if (!$('data-panel').hidden) void loadData(); });
window.addEventListener('rhythm:sources-saved', () => { if (!$('data-panel').hidden) void loadData(); });
window.addEventListener('rhythm:daily-result-saved', () => { if (!$('data-panel').hidden) void loadData(); $('alpha-modeler-frame').contentWindow?.postMessage({ type: 'rhythm:work-updated' }, location.origin); });
$('portfolio-retry').addEventListener('click', loadPortfolio);
$('project-list').addEventListener('click', async event => {
  const button = event.target.closest('[data-project]');
  if (!button) return;
  const accepted = await $('alpha-modeler-frame').contentWindow?.rhythmAlphaModeler?.selectProject(button.dataset.project);
  if (accepted === false) return;
  selectedProject = button.dataset.project; render();
});
window.addEventListener('message', event => {
  if (event.origin !== location.origin || event.source !== $('alpha-modeler-frame').contentWindow) return;
  if (event.data?.type === 'rhythm:alpha-height' && Number.isFinite(event.data.height)) $('alpha-modeler-frame').style.height = Math.max(520, Math.min(12000, event.data.height)) + 'px';
  if (event.data?.type === 'rhythm:focus-object') window.dispatchEvent(new CustomEvent('rhythm:pick-work', { detail: event.data.work }));
  if (event.data?.type === 'rhythm:alpha-ready') void syncModeler();
  if (event.data?.type === 'rhythm:alpha-saved') { void loadPortfolio(); window.dispatchEvent(new Event('rhythm:portfolio-saved')); }
});
$('alpha-modeler-frame').addEventListener('load', syncModeler);
$('alpha-parent').addEventListener('change', syncAlphaParent);
$('alpha-filled').addEventListener('change', syncFilled);
$('project-detail').addEventListener('click', async event => {
  const button = event.target.closest('button'); if (!button) return;
  if (button.id === 'edit-current-project') openProject(selectedProject);
  else if (button.id === 'add-project-zone') openZone();
  else if (button.id === 'detail-new-task') openTask();
  else if (button.dataset.alphaEdit) openAlpha(button.dataset.alphaEdit);
  else if (button.dataset.alphaChild) openAlpha(null, button.dataset.alphaChild);
  else if (button.dataset.alphaTask) openTask(button.dataset.alphaTask);
  else if (button.dataset.zoneSlot) openAlpha(null, null, button.dataset.zoneSlot);
  else if (button.dataset.taskToggle) {
    const task = portfolio.tasks.find(item => item.id === button.dataset.taskToggle);
    button.disabled = true;
    try { await request('setTaskDone', { id: task.id, done: !task.done }); notice(task.done ? 'Задача открыта снова' : 'Задача закрыта'); }
    catch (error) { button.disabled = false; notice(error.message); }
  }
});

$('project-form').addEventListener('submit', event => void submit(event, 'project-form-error', editedProject ? 'updateProject' : 'createProject', { id: editedProject, name: $('project-name').value, status: $('project-status').value, phase: $('project-phase').value, zoneIds: [...$('project-zone-options').querySelectorAll('input:checked')].map(input => input.value) }, 'project-dialog', 'Проект сохранён'));
$('zone-form').addEventListener('submit', event => void submit(event, 'zone-form-error', 'addZone', { projectId: selectedProject, title: $('zone-title').value, hint: $('zone-hint').value }, 'zone-dialog', 'Зона добавлена. Пока в ней нет слота альфы'));
$('alpha-form').addEventListener('submit', event => void submit(event, 'alpha-form-error', editedAlpha ? 'updateAlpha' : 'createAlpha', { id: editedAlpha, expectedRevision: editedAlpha ? editedAlphaRevision : undefined, projectId: selectedProject, zoneId: $('alpha-zone').value, parentId: $('alpha-parent').value || null, typeName: $('alpha-type').value, uniqueName: $('alpha-name').value, description: $('alpha-description').value, state: $('alpha-state').value, stateLabel: $('alpha-state-label').value, criteria: $('alpha-criteria').value, evidence: $('alpha-evidence').value, nextStep: $('alpha-next-step').value, filledDate: $('alpha-filled').checked ? $('alpha-filled-date').value : null }, 'alpha-dialog', 'Альфа сохранена. Зоны и недельный норматив пересчитаны'));
$('task-form').addEventListener('submit', event => void submit(event, 'task-form-error', 'createTask', { projectId: selectedProject, alphaId: $('task-alpha').value || null, title: $('task-title').value, beforeOperation: $('task-before-operation').checked }, 'task-dialog', 'Задача добавлена'));

setView(window.location.hash.slice(1));
void loadPortfolio();

if (document.modelContext?.registerTool) {
  const lifecycle = new AbortController();
  try {
    void Promise.resolve(document.modelContext.registerTool({
      name: 'read_project_dashboard', title: 'Посмотреть проекты, альфы и пробелы',
      description: 'Прочитать активные проекты, открытые задачи до эксплуатации, зоны с пробелами, карточки альф и их состояния. Не изменяет данные.',
      inputSchema: { type: 'object', properties: {}, additionalProperties: false },
      annotations: { readOnlyHint: true, untrustedContentHint: true },
      execute() { if (!portfolio) throw new Error('Проекты ещё не загружены.'); return portfolio; }
    }, { signal: lifecycle.signal })).catch(error => console.warn('WebMCP:', error.message));
  } catch (error) { console.warn('WebMCP:', error.message); }
  window.addEventListener('pagehide', () => lifecycle.abort(), { once: true });
}
