import { randomUUID } from 'node:crypto';

export const alphaStates = [
  { id: 'empty', title: 'Пустой слот' },
  { id: 'described', title: 'Описано' },
  { id: 'working', title: 'В работе' },
  { id: 'verified', title: 'Подтверждено' },
  { id: 'ready', title: 'Готово к эксплуатации' },
  { id: 'not_applicable', title: 'Не применяется' }
];
export const defaultZones = [
  { id: 'customers', title: 'Клиенты', hint: 'С кем обсуждена потребность? Запиши результаты разговоров и что они подтверждают.', typeName: 'Клиентура' },
  { id: 'economics', title: 'Финансовая модель', hint: 'Как связаны доходы, расходы и допущения? Укажи расчёт и что в нём проверено.', typeName: 'Финансовая модель' },
  { id: 'operators', title: 'Операторы и партнёры', hint: 'Кто обеспечивает работу? Зафиксируй контакты, договорённости и ответственных.', typeName: 'Операторы' }
];
const timestamp = () => new Date().toISOString();
const text = (value, label, max = 4000, required = false) => {
  if (typeof value !== 'string' || value.length > max || (required && !value.trim())) throw new Error(`${label}: ${required ? 'заполни поле; ' : ''}максимум ${max} символов.`);
  return value.trim();
};

export function initialPortfolio() {
  return { version: 1, projects: [], tasks: [], alphas: [] };
}

export function portfolioView(portfolio) {
  function inspect(alpha, ancestors = new Set()) {
    if (ancestors.has(alpha.id)) return { ok: false, issues: ['Цикл подальф'] };
    const issues = [];
    if (alpha.state === 'not_applicable') {
      if (!alpha.evidence.trim()) issues.push('Не объяснено, почему не применяется');
    } else {
      if (!alpha.filledDate) issues.push('Слот не заполнен');
      if (!['verified', 'ready'].includes(alpha.state)) issues.push('Состояние не подтверждено');
      if (!alpha.criteria.trim()) issues.push('Не задан критерий состояния');
      if (!alpha.evidence.trim()) issues.push('Нет подтверждения');
    }
    const nextAncestors = new Set([...ancestors, alpha.id]);
    const children = portfolio.alphas.filter(item => item.parentId === alpha.id);
    if (children.some(child => !inspect(child, nextAncestors).ok)) issues.push('Подальфы требуют внимания');
    return { ok: issues.length === 0, issues };
  }
  const alphas = portfolio.alphas.map(alpha => ({ ...alpha, assessment: inspect(alpha) }));
  const projects = portfolio.projects.map(project => {
    const projectAlphas = alphas.filter(alpha => alpha.projectId === project.id);
    const tasks = portfolio.tasks.filter(task => task.projectId === project.id);
    const zones = project.zones.map(zone => {
      const roots = projectAlphas.filter(alpha => alpha.zoneId === zone.id && !alpha.parentId);
      const covered = roots.length > 0 && roots.every(alpha => alpha.assessment.ok);
      return { ...zone, covered, slotCount: projectAlphas.filter(alpha => alpha.zoneId === zone.id).length, issues: roots.length ? [...new Set(roots.flatMap(alpha => alpha.assessment.issues))] : ['Нет слота альфы'] };
    });
    return { ...project, zones, summary: { slots: projectAlphas.length, filled: projectAlphas.filter(alpha => alpha.filledDate).length, coveredZones: zones.filter(zone => zone.covered).length, totalZones: zones.length, gaps: zones.filter(zone => !zone.covered).length, openTasks: tasks.filter(task => !task.done).length, beforeOperationTasks: tasks.filter(task => !task.done && task.beforeOperation).length } };
  });
  const active = new Set(projects.filter(project => project.status === 'active').map(project => project.id));
  return { projects, alphas, tasks: portfolio.tasks, states: alphaStates, defaultZones,
    summary: { activeProjects: active.size, openTasks: portfolio.tasks.filter(task => active.has(task.projectId) && !task.done).length, beforeOperationTasks: portfolio.tasks.filter(task => active.has(task.projectId) && !task.done && task.beforeOperation).length, gapZones: projects.filter(project => active.has(project.id)).reduce((sum, project) => sum + project.summary.gaps, 0) }
  };
}

export function changePortfolio(portfolio, action, input, validDate) {
  const next = structuredClone(portfolio);
  const now = timestamp();
  const projectFor = id => { const project = next.projects.find(item => item.id === id); if (!project) throw new Error('Проект не найден.'); return project; };
  const alphaFor = id => { const alpha = next.alphas.find(item => item.id === id); if (!alpha) throw new Error('Альфа не найдена.'); return alpha; };
  if (action === 'createProject' || action === 'updateProject') {
    const project = action === 'updateProject' ? projectFor(input.id) : { id: randomUUID(), createdAt: now, zones: [] };
    const name = text(input.name, 'Название проекта', 120, true);
    if (!['active', 'paused', 'closed'].includes(input.status)) throw new Error('Выбери статус проекта.');
    if (!['pre_operation', 'operation'].includes(input.phase)) throw new Error('Выбери этап проекта.');
    if (!Array.isArray(input.zoneIds) || input.zoneIds.some(id => typeof id !== 'string')) throw new Error('Выбери зоны проекта.');
    const available = [...project.zones, ...defaultZones.filter(zone => !project.zones.some(item => item.id === zone.id))];
    if (input.zoneIds.some(id => !available.some(zone => zone.id === id))) throw new Error('Неизвестная зона.');
    const zones = available.filter(zone => input.zoneIds.includes(zone.id));
    if (!zones.length) throw new Error('Выбери хотя бы одну зону для отслеживания.');
    if (next.alphas.some(alpha => alpha.projectId === project.id && !zones.some(zone => zone.id === alpha.zoneId))) throw new Error('В отключаемой зоне есть альфы. Перенеси их в другую зону.');
    Object.assign(project, { name, status: input.status, phase: input.phase, zones, updatedAt: now });
    if (action === 'createProject') next.projects.push(project);
  } else if (action === 'addZone') {
    const project = projectFor(input.projectId);
    const title = text(input.title, 'Название зоны', 100, true);
    if (project.zones.some(zone => zone.title.toLocaleLowerCase('ru') === title.toLocaleLowerCase('ru'))) throw new Error('Такая зона уже есть в проекте.');
    project.zones.push({ id: randomUUID(), title, hint: text(input.hint ?? '', 'Подсказка', 600), typeName: title });
    project.updatedAt = now;
  } else if (action === 'createAlpha' || action === 'updateAlpha') {
    const alpha = action === 'updateAlpha' ? alphaFor(input.id) : { id: randomUUID(), projectId: input.projectId, createdAt: now };
    const project = projectFor(alpha.projectId);
    const parentId = input.parentId || null;
    let zoneId = input.zoneId;
    if (parentId) {
      const parent = alphaFor(parentId);
      if (parent.projectId !== project.id) throw new Error('Подальфа должна относиться к тому же проекту.');
      let cursor = parent;
      const seen = new Set();
      while (cursor) {
        if (cursor.id === alpha.id || seen.has(cursor.id)) throw new Error('Альфа не может быть подальфой самой себя или своего потомка.');
        seen.add(cursor.id);
        cursor = cursor.parentId ? alphaFor(cursor.parentId) : null;
      }
      zoneId = parent.zoneId;
    }
    if (!project.zones.some(zone => zone.id === zoneId)) throw new Error('Выбери зону проекта.');
    const typeName = text(input.typeName, 'Типовое имя', 120, true);
    const uniqueName = text(input.uniqueName ?? '', 'Уникальное имя', 180);
    if (uniqueName && next.alphas.some(item => item.id !== alpha.id && item.projectId === project.id && item.uniqueName.toLocaleLowerCase('ru') === uniqueName.toLocaleLowerCase('ru'))) throw new Error('В этом проекте уже есть альфа с таким уникальным именем.');
    if (!alphaStates.some(state => state.id === input.state)) throw new Error('Выбери состояние альфы.');
    const description = text(input.description ?? '', 'Описание');
    const filledDate = input.filledDate ?? null;
    if (filledDate !== null && (!validDate(filledDate) || !uniqueName || !description || ['empty', 'not_applicable'].includes(input.state))) throw new Error('Чтобы учесть заполнение, нужны уникальное имя, описание, состояние и корректная дата.');
    Object.assign(alpha, { parentId, zoneId, typeName, uniqueName, description, state: input.state, stateLabel: text(input.stateLabel ?? '', 'Состояние по шаблону', 160), criteria: text(input.criteria ?? '', 'Критерий состояния'), evidence: text(input.evidence ?? '', 'Подтверждение'), nextStep: text(input.nextStep ?? '', 'Следующий шаг', 1000), filledDate, updatedAt: now });
    if (action === 'createAlpha') next.alphas.push(alpha);
    function moveChildren(id) { for (const child of next.alphas.filter(item => item.parentId === id)) { child.zoneId = zoneId; child.updatedAt = now; moveChildren(child.id); } }
    moveChildren(alpha.id);
  } else if (action === 'createTask') {
    const project = projectFor(input.projectId);
    const alphaId = input.alphaId || null;
    if (alphaId && alphaFor(alphaId).projectId !== project.id) throw new Error('Задача и альфа должны относиться к одному проекту.');
    if (typeof input.beforeOperation !== 'boolean') throw new Error('Укажи, нужна ли задача до эксплуатации.');
    next.tasks.push({ id: randomUUID(), projectId: project.id, alphaId, title: text(input.title, 'Задача', 300, true), beforeOperation: input.beforeOperation, done: false, createdAt: now, updatedAt: now });
  } else if (action === 'setTaskDone') {
    const task = next.tasks.find(item => item.id === input.id);
    if (!task) throw new Error('Задача не найдена.');
    if (typeof input.done !== 'boolean') throw new Error('Некорректный статус задачи.');
    task.done = input.done;
    task.updatedAt = now;
  } else throw new Error('Неизвестное действие.');
  return next;
}
