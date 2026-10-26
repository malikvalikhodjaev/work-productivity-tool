import { randomUUID } from 'node:crypto';
import { nativeCommandGuard, nativeId, assertNativeBase } from './native-commands.mjs';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { replaceFile } from './atomic-file.mjs';
import { dirname } from 'node:path';
import { today, validDate, metrics } from './store.mjs';
import {changeWorkRecords} from './work-items.mjs';
import {checkedParent} from './entity-hierarchy.mjs';
import {goalHierarchySignature,relocateGoal} from './goal-hierarchy.mjs';
import {changeGoalGrid,goalGridColumns} from './goal-grid.mjs';

const str = (value, label, max = 1000, required = false) => {
  if (typeof value !== 'string' || value.length > max || (required && !value.trim())) throw new Error(`${label}: ${required ? 'заполни поле; ' : ''}не больше ${max} символов.`);
  return value.trim();
};
const num = value => {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || Math.abs(value) > 1e12) throw new Error('Укажи конечное число от −10¹² до 10¹².');
  return value;
};
const choose = (value, options) => { if (!options.includes(value)) throw new Error('Неизвестное значение: ' + String(value)); return value; };
const date = (value, optional = false) => { if (optional && !value) return null; if (!validDate(value)) throw new Error('Укажи корректную дату.'); return value; };
const timestamp = () => new Date().toISOString();

export function progress(baseline, current, target, direction) {
  if (current === null || target === null) return { percent: null, reached: null };
  const reached = direction === 'up' ? current >= target : current <= target;
  if (baseline === null || target === baseline) return { percent: null, reached };
  return { percent: Math.round(Math.max(0, Math.min(100, (current - baseline) / (target - baseline) * 100))), reached };
}

const nativeStorage = { existsSync, mkdirSync, readFileSync, writeFileSync, replaceFile };
export function createWorkspaceStore(file, getPortfolio, { storage = nativeStorage } = {}) {
  const { existsSync, mkdirSync, readFileSync, writeFileSync, replaceFile } = storage;
  mkdirSync(dirname(file), { recursive: true });
  let data = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : { version: 1, systems: [], cases: [], goals: [], links: [], measurements: [], reviews: [], transactions: [], imports: [] };
  const native = nativeCommandGuard(() => data);
  for (const key of ['systems', 'cases', 'goals', 'links', 'measurements', 'reviews', 'transactions', 'imports']) {
    if (data.version !== 1 || !Array.isArray(data[key])) throw new Error('Неподдерживаемое хранилище результатов. Исходник сохранён.');
  }
  for(const key of ['workItems','workNotes','workRequests']) if(data[key]!==undefined&&!Array.isArray(data[key]))throw new Error('Неподдерживаемые карточки работы. Исходник сохранён.');
  for(const key of ['goalColumns','goalTableHistory']) if(data[key]!==undefined&&!Array.isArray(data[key]))throw new Error('Неподдерживаемые столбцы индикаторов. Исходник сохранён.');
  function save(next) {
    next = native.prepare(next);
    next.updatedAt = timestamp();
    writeFileSync(file + '.tmp', JSON.stringify(next, null, 2) + '\n', 'utf8');
    replaceFile(file + '.tmp', file);
    data = next;
  }
  function entities() {
    const portfolio = getPortfolio();
    return [
      ...data.systems.map(x => ({ ref: `system:${x.id}`, title: x.name, type: 'system' })),
      ...data.cases.map(x => ({ ref: `case:${x.id}`, title: x.title, type: 'case', parentRef: x.projectId ? `project:${x.projectId}` : null })),
      ...(data.workItems??[]).map(x=>({ref:`work:${x.id}`,title:x.title,type:'work',parentRef:x.projectId?`project:${x.projectId}`:null})),
      ...portfolio.projects.map(x => ({ ref: `project:${x.id}`, title: x.name, type: 'project' })),
      ...portfolio.tasks.map(x => ({ ref: `task:${x.id}`, title: x.title, type: 'task', parentRef: `project:${x.projectId}` })),
      ...portfolio.alphas.map(x => ({ ref: `alpha:${x.id}`, title: x.uniqueName || x.typeName, type: 'alpha', parentRef: `project:${x.projectId}` }))
    ];
  }
  function validateRef(ref) {
    if (ref === null || ref === undefined || ref === '') return null;
    if (typeof ref !== 'string' || !entities().some(x => x.ref === ref)) throw new Error('Связанный объект не найден.');
    return ref;
  }
  function characteristic(id) {
    const system = data.systems.find(x => x.characteristics.some(c => c.id === id));
    if (!system) throw new Error('Характеристика не найдена.');
    return { ...system.characteristics.find(c => c.id === id), systemId: system.id, systemName: system.name };
  }
  function latest(kind, id) {
    return data.measurements.filter(m => m.kind === kind && m.targetId === id)
      .sort((a, b) => b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt) || data.measurements.indexOf(b) - data.measurements.indexOf(a))[0] ?? null;
  }
  function evaluate(c) {
    const measurement = latest('characteristic', c.id);
    const current = measurement?.value ?? null;
    return { ...c, current, measurement, ...progress(c.baseline, current, c.target, c.direction), violation: c.kind === 'limit' && current !== null && c.target !== null ? current > c.target : null };
  }
  function view() {
    const systems = data.systems.map(s => ({ ...s, characteristics: s.characteristics.map(evaluate) }));
    const goals = data.goals.map(g => {
      const c = g.characteristicId ? characteristic(g.characteristicId) : null;
      const measurement = latest(c ? 'characteristic' : 'goal', c?.id ?? g.id);
      const current = measurement?.value ?? null;
      return { ...g, current, measurement, unit: c?.unit ?? g.unit, ...progress(g.baseline, current, g.target, g.direction), systemName: c?.systemName ?? null };
    });
    const cases = data.cases.map(c => ({ ...c, review: data.reviews.filter(r => r.caseId === c.id).at(-1) ?? null,
      overdue: c.status !== 'closed' && !!c.nextReview && c.nextReview < today() }));
    const {workRequests,nativeRequests,...visible}=data;
    return { ...visible, goalHierarchyVersion: 1, goalGridVersion: 1, goalColumnDefinitions: goalGridColumns(data), goalTrashVersion: 1, workItems:data.workItems??[],workNotes:data.workNotes??[], systems, goals, cases, entities: entities(), today: today() };
  }
  function problemCase(problemDate) {
    return structuredClone(data.cases.find(item=>item.dailyProblem?.date===problemDate||item.dailyProblem?.dates?.includes(problemDate))??null);
  }
  function ensureProblemCase(problem, clientId = null) {
    if(!problem||!validDate(problem.date)||problem.date>today()||typeof problem.text!=='string'||!problem.text.trim()||problem.text.length>2000||!Number.isFinite(Date.parse(problem.updatedAt)))throw new Error('Сначала сохрани корректную проблему дня.');
    let previous=data.cases.find(item=>item.dailyProblem?.date===problem.date||item.dailyProblem?.dates?.includes(problem.date));
    if(!previous){const text=problem.text.trim();const matching=data.cases.filter(item=>(item.dailyProblem?.versions.at(-1)?.text??item.context??'').trim()===text||(!item.dailyProblem&&item.title===text));if(matching.length>1)throw new Error('Есть несколько кейсов с этой формулировкой. Уточни проблему или названия кейсов.');previous=matching[0];}
    if(previous?.dailyProblem?.versions.some(version=>version.date===problem.date&&version.problemUpdatedAt===problem.updatedAt))return {case:structuredClone(previous),created:false};
    const next=structuredClone(data),stamp=timestamp();
    const version={date:problem.date,text:problem.text,problemUpdatedAt:problem.updatedAt,capturedAt:stamp};
    let item;
    if(previous){item=next.cases.find(item=>item.id===previous.id);item.dailyProblem??={date:problem.date,dates:[],original:structuredClone(problem),versions:[]};item.dailyProblem.dates=[...new Set([item.dailyProblem.date,...(item.dailyProblem.dates??[]),problem.date])];item.dailyProblem.versions.push(version);item.updatedAt=stamp;}
    else{if(clientId&&(!nativeId(clientId)||next.cases.some(c=>c.id===clientId)))throw new Error('Некорректный или занятый UUID кейса устройства.');const text=problem.text.trim();item={id:clientId??randomUUID(),title:text.length>200?text.slice(0,199).replace(/[\uD800-\uDBFF]$/,'')+'…':text,projectId:null,status:'active',context:problem.text,nextStep:'',nextReview:null,resolution:'',createdAt:stamp,updatedAt:stamp,dailyProblem:{date:problem.date,dates:[problem.date],original:structuredClone(problem),versions:[version]}};next.cases.push(item);}
    save(next);
    return {case:structuredClone(item),created:!previous};
  }
  function mutate(action, input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new Error('Нужен объект данных.');
    if (input.clientId !== undefined && !nativeId(input.clientId)) throw new Error('Некорректный UUID нового объекта.');
    const nativeCollection = { saveCase: 'cases', saveGoal: 'goals', saveSystem: 'systems' }[action];
    if (!input.id && input.clientId && nativeCollection && data[nativeCollection].some(x => x.id === input.clientId)) throw new Error('UUID нового объекта уже занят.');
    if(action==='moveGoal') {
      if(input.expectedHierarchy!==goalHierarchySignature(data.goals)) {
        const error=new Error('Иерархия индикаторов уже изменилась. Перемещение сохранено для разбора.');error.status=409;throw error;
      }
      const goals=relocateGoal(data.goals,input),next=structuredClone(data);
      next.goals=goals;next.goalTableHistory??=[];
      next.goalTableHistory.push({id:randomUUID(),at:timestamp(),action:'moveGoal',rowId:input.id,
        before:data.goals.map(g=>({id:g.id,parentId:g.parentId??null,sortOrder:g.sortOrder??null})),
        value:goals.map(g=>({id:g.id,parentId:g.parentId??null,sortOrder:g.sortOrder??null}))});
      save(next);return view();
    }
    if(['createGoalColumn','updateGoalColumn','editGoalCell'].includes(action)) {
      save(changeGoalGrid(data,action,input,validDate)); return view();
    }
    if(['saveWorkItem','saveWorkNote'].includes(action)) {
      const changed=changeWorkRecords(data,action,input,{validateRef,validDate,metrics});
      if(!changed.duplicate) save(changed.next);
      return view();
    }
    const next = structuredClone(data);
    const existing = (list, id) => { const item = next[list].find(x => x.id === id); if (!item) throw new Error('Объект не найден.'); return item; };
    if (action === 'saveSystem') {
      const system = input.id ? existing('systems', input.id) : { id: input.clientId ?? randomUUID(), createdAt: timestamp() };
      if (!Array.isArray(input.characteristics) || input.characteristics.length < 4 || input.characteristics.length > 10) throw new Error('Нужны три приоритета и хотя бы один ограничитель (до 10 характеристик).');
      const old = new Map((system.characteristics ?? []).map(c => [c.id, c]));
      const used = new Set();
      const characteristics = input.characteristics.map((c, i) => {
        const kind = i < 3 ? 'priority' : 'limit';
        const id = c.id || randomUUID();
        if ((c.id && !old.has(c.id)) || used.has(id)) throw new Error('Некорректный идентификатор характеристики.');
        used.add(id);
        const result = { id, kind, name: str(c.name ?? '', 'Характеристика', 120), unit: str(c.unit ?? '', 'Единица', 30), baseline: num(c.baseline), target: num(c.target), direction: kind === 'limit' ? 'down' : choose(c.direction, ['up', 'down']) };
        if (result.baseline !== null && result.target !== null && kind === 'priority' && (result.direction === 'up' ? result.target < result.baseline : result.target > result.baseline)) throw new Error('Целевое значение противоречит направлению изменения.');
        const previous = old.get(id);
        if (previous && data.measurements.some(m => m.targetId === id) && (previous.unit !== result.unit || previous.name !== result.name)) throw new Error('У измеренной характеристики нельзя менять смысл и единицу. Создай новую систему или характеристику для новой шкалы.');
        return result;
      });
      if ([...old.keys()].some(id => !used.has(id))) throw new Error('Удаление характеристик с историей пока не поддерживается.');
      Object.assign(system, { name: str(input.name, 'Система', 180, true), description: str(input.description ?? '', 'Описание', 3000), characteristics, updatedAt: timestamp() });
      if (!input.id) next.systems.push(system);
    } else if (action === 'measure') {
      const kind = choose(input.kind, ['characteristic', 'goal']);
      const target = kind === 'characteristic' ? characteristic(input.targetId) : existing('goals', input.targetId);
      if (kind === 'goal' && target.characteristicId) throw new Error('Внеси замер связанной характеристики системы.');
      if (kind === 'characteristic' && !target.name) throw new Error('Сначала назови характеристику.');
      const value = num(input.value);
      if (value === null) throw new Error('Укажи измеренное значение.');
      const measuredAt = date(input.date);
      if (measuredAt > today()) throw new Error('Факт нельзя датировать будущим.');
      const evidence = str(input.evidence ?? '', 'Подтверждение', 3000, true);
      next.measurements.push({ id: randomUUID(), kind, targetId: input.targetId, value, date: measuredAt, evidence, workRef: validateRef(input.workRef), createdAt: timestamp() });
    } else if (action === 'saveLink') {
      const ownerRef = validateRef(input.ownerRef);
      if (!ownerRef || ownerRef.startsWith('system:')) throw new Error('Выбери проект, кейс, задачу или альфу.');
      next.links = next.links.filter(x => x.ownerRef !== ownerRef);
      if (input.systemId) {
        const system = existing('systems', input.systemId);
        const notes = input.notes ?? {};
        if (!notes || typeof notes !== 'object' || Array.isArray(notes) || Object.keys(notes).some(id => !system.characteristics.some(c => c.id === id))) throw new Error('Проверь связи характеристик.');
        next.links.push({ ownerRef, systemId: system.id, notes: Object.fromEntries(Object.entries(notes).map(([id, note]) => [id, str(note, 'Ожидаемое влияние', 600)])), updatedAt: timestamp() });
      }
    } else if (action === 'saveGoal') {
      const goal = input.id ? existing('goals', input.id) : { id: input.clientId ?? randomUUID(), createdAt: timestamp() };
      if (Object.hasOwn(input, 'trashedAt')) {
        if (input.trashedAt !== null && (typeof input.trashedAt !== 'string' || !/^\d{4}-\d{2}-\d{2}T/.test(input.trashedAt) || !Number.isFinite(Date.parse(input.trashedAt)))) throw new Error('Некорректная дата удаления цели.');
        goal.trashedAt = input.trashedAt;
      }
      if (Object.hasOwn(input, 'physicalSystem')) {
        if (typeof input.physicalSystem !== 'string' || input.physicalSystem.length > 2000) throw new Error('Физическая система: текст до 2000 символов.');
        if (goal.physicalSystem !== input.physicalSystem) {
          next.goalTableHistory ??= [];
          next.goalTableHistory.push({id:randomUUID(),at:timestamp(),rowId:goal.id,columnId:'physicalSystem',before:goal.physicalSystem??null,value:input.physicalSystem});
        }
        goal.physicalSystem = input.physicalSystem;
      }
      const parentId = checkedParent(next.goals, goal.id, Object.hasOwn(input, 'parentId') ? input.parentId : goal.parentId);
      const c = input.characteristicId ? characteristic(input.characteristicId) : null;
      if (goal.id && data.measurements.some(m => m.kind === 'goal' && m.targetId === goal.id) && (goal.unit !== input.unit || (goal.characteristicId ?? null) !== (input.characteristicId ?? null))) throw new Error('Не меняй источник или единицу цели с замерами; создай новую цель.');
      const baseline = num(input.baseline), target = num(input.target), direction = choose(input.direction, ['up', 'down']);
      if (baseline !== null && target !== null && (direction === 'up' ? target < baseline : target > baseline)) throw new Error('Проверь направление и цель.');
      Object.assign(goal, { title: str(input.title, 'Цель', 200, true), characteristicId: c?.id ?? null, workRef: validateRef(input.workRef), unit: c?.unit ?? str(input.unit ?? '', 'Единица', 30), baseline, target, direction, dueDate: date(input.dueDate, true), status: choose(input.status ?? 'active', ['note', 'planned', 'active', 'commissioning', 'ready', 'operation', 'blocked', 'retired', 'paused', 'archived']), updatedAt: timestamp() });
      goal.parentId = parentId;
      if (!input.id) next.goals.push(goal);
    } else if (action === 'saveCase') {
      const item = input.id ? existing('cases', input.id) : { id: input.clientId ?? randomUUID(), createdAt: timestamp() };
      if (input.projectId) validateRef(`project:${input.projectId}`);
      const status = choose(input.status, ['new', 'active', 'watching', 'closed']);
      const resolution = str(input.resolution ?? '', 'Результат', 2000);
      if (status === 'closed' && !resolution) throw new Error('Для закрытия кейса укажи результат и основание.');
      Object.assign(item, { title: str(input.title, 'Кейс', 200, true), projectId: input.projectId || null, status, context: str(input.context ?? '', 'Ситуация', 4000), nextStep: str(input.nextStep ?? '', 'Следующий ход', 1000), nextReview: date(input.nextReview, true), resolution, updatedAt: timestamp() });
      if (!input.id) next.cases.push(item);
    } else if (action === 'reviewCase') {
      const item = existing('cases', input.caseId);
      const reviewDate = date(input.date);
      if (reviewDate > today()) throw new Error('Диагностика не может быть в будущем.');
      const review = { id: randomUUID(), caseId: item.id, date: reviewDate, facts: str(input.facts, 'Наблюдения', 3000, true), unknowns: str(input.unknowns ?? '', 'Неизвестное', 2000), nextStep: str(input.nextStep, 'Следующий ход или наблюдение', 1000, true), nextReview: date(input.nextReview), createdAt: timestamp() };
      if (review.nextReview < reviewDate) throw new Error('Следующая проверка не может быть раньше диагностики.');
      next.reviews.push(review);
      Object.assign(item, { nextStep: review.nextStep, nextReview: review.nextReview, updatedAt: timestamp() });
    } else throw new Error('Неизвестное действие.');
    save(next);
    return view();
  }
  function normalizeTransaction(input) {
    const amount = num(input.amount);
    if (amount === null || amount <= 0 || Math.abs(amount * 100 - Math.round(amount * 100)) > 0.001) throw new Error('Сумма должна быть положительной, не больше двух знаков после запятой.');
    const currency = str(input.currency, 'Валюта', 3, true).toUpperCase();
    if (!/^[A-Z]{3}$/.test(currency)) throw new Error('Код валюты: три латинские буквы, например UZS.');
    const occurredAt = date(input.date);
    if (occurredAt > today()) throw new Error('Фактическая операция не может быть в будущем.');
    return { date: occurredAt, amountMinor: Math.round(amount * 100), currency, type: choose(input.type, ['income', 'expense', 'transfer']), category: str(input.category ?? '', 'Категория', 120), description: str(input.description ?? '', 'Описание', 500), workRef: validateRef(input.workRef) };
  }
  function addTransaction(input) {
    const transaction = { ...normalizeTransaction(input), id: randomUUID(), source: 'manual', createdAt: timestamp() };
    save({ ...data, transactions: [...data.transactions, transaction] });
    return transaction;
  }
  function correctTransaction(id, input) {
    const existing = data.transactions.find(t => t.id === id);
    if (!existing) throw new Error('Операция не найдена.');
    const { revisions, ...previous } = existing;
    const transaction = { ...existing, ...normalizeTransaction(input), revisions: [...(revisions ?? []), { ...previous, revisedAt: timestamp() }] };
    save({ ...data, transactions: data.transactions.map(t => t.id === id ? transaction : t) });
    return transaction;
  }
  function importTransactions(rows, source, commit = false) {
    source = str(source, 'Источник', 80, true);
    if (source === 'manual') throw new Error('Задай отдельное имя источника выгрузки.');
    if (!Array.isArray(rows) || !rows.length || rows.length > 10000) throw new Error('В файле должно быть от 1 до 10 000 операций.');
    const errors = [], ready = [], duplicates = [];
    const known = new Map(data.transactions.filter(t => t.source === source).map(t => [t.externalId, t]));
    rows.forEach((row, index) => {
      try {
        const externalId = str(row.externalId, 'ID операции', 200, true);
        const transaction = normalizeTransaction(row);
        const previous = known.get(externalId);
        if (previous) {
          const same = ['date', 'amountMinor', 'currency', 'type', 'category', 'description', 'workRef'].every(key => previous[key] === transaction[key]);
          if (!same) throw new Error('ID уже существует с другими данными. Требуется сверка; импорт не перезаписывает историю.');
          duplicates.push(index + 2);
        } else {
          const value = { ...transaction, source, externalId };
          known.set(externalId, value); ready.push(value);
        }
      } catch (error) { errors.push({ row: index + 2, error: error.message }); }
    });
    if (commit) {
      if (errors.length) throw new Error(`Импорт отменён: ${errors.length} строк с ошибками. Исправь файл и проверь снова.`);
      const importId = randomUUID(), createdAt = timestamp();
      save({ ...data, transactions: [...data.transactions, ...ready.map(t => ({ ...t, id: randomUUID(), importId, createdAt }))], imports: [...data.imports, { id: importId, source, imported: ready.length, duplicates: duplicates.length, createdAt }] });
    }
    return { valid: ready.length, duplicates: duplicates.length, errors, preview: ready.slice(0, 8), committed: commit };
  }
  function finance(start, end) {
    const transactions = data.transactions.filter(t => t.date >= start && t.date <= end);
    const currencies = [...new Set(transactions.map(t => t.currency))].sort().map(currency => {
      const rows = transactions.filter(t => t.currency === currency);
      const sum = type => rows.filter(t => t.type === type).reduce((n, t) => n + t.amountMinor, 0) / 100;
      return { currency, income: sum('income'), expense: sum('expense'), net: sum('income') - sum('expense'), transfers: sum('transfer'), count: rows.length };
    });
    return { start, end, currencies, transactions: [...transactions].sort((a,b) => b.date.localeCompare(a.date)), imports: data.imports };
  }
  function nativeMutate(command) {
    const result = native.run(command, () => {
      const input = command.input;
      const collections = { saveCase: 'cases', saveGoal: 'goals', saveSystem: 'systems' };
      if (collections[command.action]) {
        const list = data[collections[command.action]];
        if (input.clientId && (!nativeId(input.clientId) || list.some(x => x.id === input.clientId))) throw new Error('Некорректный или занятый UUID объекта.');
        if (!input.id && !input.clientId) throw new Error('Для нового объекта нужен UUID устройства.');
        assertNativeBase(input.id ? list.find(x => x.id === input.id) : null, command.expectedUpdatedAt);
      }
      if (command.action === 'saveLink') assertNativeBase(data.links.find(x => x.ownerRef === input.ownerRef), command.expectedUpdatedAt);
      if (command.action === 'reviewCase') assertNativeBase(data.cases.find(x => x.id === input.caseId), command.expectedUpdatedAt);
      if(command.action==='saveGoal'&&input.id) {
        const parent=data.goals.find(g=>g.id===input.id)?.parentId??null;
        // Moving a branch must not be undone by an old full-row draft.
        const expected=Object.hasOwn(input,'expectedParentId')?input.expectedParentId||null:Object.hasOwn(input,'parentId')?input.parentId||null:parent;
        if(parent!==expected) {const error=new Error('Родитель индикатора уже изменился. Текст правки сохранён для разбора.');error.status=409;throw error;}
      }
      if (!['saveCase', 'saveGoal', 'saveSystem', 'measure', 'saveLink', 'reviewCase', 'saveWorkItem', 'saveWorkNote', 'createGoalColumn', 'updateGoalColumn', 'editGoalCell', 'moveGoal'].includes(command.action)) throw new Error('Неизвестная команда приложения.');
      mutate(command.action, input);
    });
    return { ...result, workspace: view() };
  }
  return { view, mutate, nativeMutate, entities, validateRef, problemCase, ensureProblemCase, addTransaction, correctTransaction, importTransactions, finance };
}
