import { randomUUID } from 'node:crypto';
import { changePortfolio, alphaStates } from './portfolio.mjs';
import { checkTableColumns, checkedCustomValues } from './portfolio-grid.mjs';
import {compileReferenceTemplate,validateAlphaTemplateFields} from './project-templates.mjs';

const fields = ['projectId', 'parentId', 'zoneId', 'typeName', 'uniqueName', 'description', 'state', 'stateLabel', 'criteria', 'evidence', 'nextStep', 'filledDate', 'adaptedAlpha', 'area', 'whyImportant', 'source', 'metaAdaptation', 'systemTime', 'attention', 'reviewDate'];
export function alphaSnapshot(alpha) {
  return {...Object.fromEntries(fields.map(key => [key, alpha[key] ?? (['parentId', 'filledDate', 'reviewDate'].includes(key) ? null : '')])), ...(alpha.customValues ? {customValues:structuredClone(alpha.customValues)} : {}), ...Object.fromEntries(['sortOrder','templateStates','templateQuestions','templateOrigin'].filter(key=>alpha[key]!==undefined).map(key=>[key,structuredClone(alpha[key])]))};
}

const checkedText = (value, max) => typeof value === 'string' && value.trim() && value.length <= max;
export function mergeAlphaBackup(current, payload, validDate) {
  if (!payload || payload.format !== 'alpha-modeler' || payload.version !== 1 || !Array.isArray(payload.projects) || !Array.isArray(payload.alphas) || !Array.isArray(payload.history ?? [])) throw new Error('Выбери JSON-экспорт моделера альф версии 1.');
  if (payload.projects.length > 200 || payload.alphas.length > 3000 || (payload.history?.length ?? 0) > 20000) throw new Error('Импорт слишком большой.');
  let portfolio = structuredClone(current);
  if(payload.templateVersions!==undefined){
    if(!payload.templateVersions||typeof payload.templateVersions!=='object'||Array.isArray(payload.templateVersions)||Object.keys(payload.templateVersions).length>200)throw new Error('Некорректные версии шаблонов.');
    portfolio.templateVersions ??= {};
    for(const [version,source]of Object.entries(payload.templateVersions)){
      const template=compileReferenceTemplate({rows:source.sourceRows,sources:source.sources,capturedAt:source.capturedAt});
      if(!template||template.version!==version)throw new Error('Версия шаблона не совпадает с исходными строками.');
      portfolio.templateVersions[version] ??= structuredClone(source);
    }
  }
  const schema=checkTableColumns(payload.tableColumns);
  let columnsAdded=0, projectsAdded=0;
  portfolio.tableColumns ??= {};
  for (const [table,columns] of Object.entries(schema)) {
    const target=portfolio.tableColumns[table] ??= [];
    for (const column of columns) {
      const existing=target.find(c=>c.id===column.id);
      if(existing) {
        if(existing.type!==column.type||JSON.stringify(existing.options ?? {})!==JSON.stringify(column.options ?? {})) throw new Error('Тип или варианты столбца отличаются. Исходный файл сохранён; импорт отменён.');
      } else {target.push(column);columnsAdded++;}
    }
    if(target.length>100)throw new Error('После импорта получится больше 100 дополнительных столбцов.');
  }
  const projects = new Map(); const seen = new Set();
  for (const project of payload.projects) {
    if (!project || !checkedText(project.id, 200) || !checkedText(project.name, 120) || projects.has(project.id) || !['active', 'paused', 'closed'].includes(project.status) || !['pre_operation', 'operation'].includes(project.phase) || !Array.isArray(project.zones) || !project.zones.length || project.zones.length > 100) throw new Error('Некорректный проект в файле.');
    const zones = new Set();
    for (const zone of project.zones) {
      if (!zone || !checkedText(zone.id, 200) || !checkedText(zone.title, 100) || zones.has(zone.id)) throw new Error('Некорректная зона в файле.');
      zones.add(zone.id);
    }
    projects.set(project.id, project);
    checkedCustomValues(project.customValues,portfolio.tableColumns.projects ?? [],validDate);
  }
  // New exports also carry empty projects; never replace an existing local project.
  if(payload.tableColumns) for(const project of projects.values()) if(!portfolio.projects.some(p=>p.id===project.id)) {
    const now=new Date().toISOString();
    portfolio.projects.push({...structuredClone(project),createdAt:project.createdAt ?? now,updatedAt:project.updatedAt ?? now});projectsAdded++;
  }
  const pending = []; const conflicts = []; let unchanged = 0;
  for (const alpha of payload.alphas) {
    if (!alpha || !checkedText(alpha.id, 200) || seen.has(alpha.id) || !projects.has(alpha.projectId)) throw new Error('Некорректный идентификатор или проект альфы в файле.');
    seen.add(alpha.id);
    validateAlphaTemplateFields(alpha);
    checkedCustomValues(alpha.customValues,portfolio.tableColumns.alphas ?? [],validDate);
    const existing = portfolio.alphas.find(item => item.id === alpha.id);
    if (existing) {
      if (JSON.stringify(alphaSnapshot(existing)) === JSON.stringify(alphaSnapshot(alpha))) unchanged++;
      else conflicts.push({ id: alpha.id, name: alpha.uniqueName || alpha.typeName });
    } else pending.push(alpha);
  }
  const importedIds = new Set();
  while (pending.length) {
    const index = pending.findIndex(alpha => !alpha.parentId || portfolio.alphas.some(item => item.id === alpha.parentId));
    if (index < 0) throw new Error('В файле есть цикл или отсутствующая родительская альфа.');
    const [alpha] = pending.splice(index, 1);
    if (!portfolio.projects.some(item => item.id === alpha.projectId)) {
      const source = projects.get(alpha.projectId); const now = new Date().toISOString();
      portfolio.projects.push({ id: source.id, name: source.name, status: source.status, phase: source.phase, zones: source.zones.map(zone => ({ id: zone.id, title: zone.title, hint: typeof zone.hint === 'string' ? zone.hint.slice(0, 600) : '', typeName: typeof zone.typeName === 'string' ? zone.typeName.slice(0, 120) : zone.title })), createdAt: now, updatedAt: now });
    }
    portfolio = changePortfolio(portfolio, 'createAlpha', alphaSnapshot(alpha), validDate);
    const added = portfolio.alphas.at(-1);
    Object.assign(added,alphaSnapshot(alpha));
    added.id = alpha.id; added.revision = 1;
    // Only add new records. Existing local records and project settings always win.
    importedIds.add(alpha.id);
    portfolio.history ??= [];
    portfolio.history.push({ id: randomUUID(), alphaId: added.id, at: added.updatedAt, action: 'import', snapshot: alphaSnapshot(added) });
  }
  for (const entry of payload.history ?? []) {
    if (!importedIds.has(entry?.alphaId)) continue;
    if (!checkedText(entry.id, 200) || !checkedText(entry.at, 80) || !Number.isFinite(Date.parse(entry.at)) || !['create', 'edit', 'baseline', 'import'].includes(entry.action) || !entry.snapshot || typeof entry.snapshot !== 'object') throw new Error('Некорректная история в файле.');
    const alpha = portfolio.alphas.find(item => item.id === entry.alphaId);
    const snapshot = alphaSnapshot(entry.snapshot);
    validateAlphaTemplateFields(snapshot);
    checkedCustomValues(snapshot.customValues,portfolio.tableColumns.alphas ?? [],validDate);
    if (snapshot.projectId !== alpha.projectId || !alphaStates.some(state => state.id === snapshot.state) || fields.some(key => snapshot[key] !== null && (typeof snapshot[key] !== 'string' || snapshot[key].length > 4000)) || ['reviewDate','filledDate'].some(key => snapshot[key] !== null && !validDate(snapshot[key]))) throw new Error('Некорректные поля истории в файле.');
    if (!portfolio.history.some(item => item.id === entry.id)) portfolio.history.push({ id: entry.id, alphaId: entry.alphaId, at: entry.at, action: entry.action, snapshot });
  }
  if(payload.tableHistory!==undefined) {
    if(!Array.isArray(payload.tableHistory)||payload.tableHistory.length>20000)throw new Error('Некорректная история таблиц.');
    portfolio.tableHistory ??= [];
    for(const event of payload.tableHistory) {
      if(!event||!['projects','alphas'].includes(event.table)||!checkedText(event.id,200)||!checkedText(event.rowId,200)||!Number.isFinite(Date.parse(event.at))||!Array.isArray(event.changes)||event.changes.length>100)throw new Error('Некорректная запись истории таблицы.');
      if(portfolio.tableHistory.some(e=>e.id===event.id))continue;
      if((event.table==='alphas'&&importedIds.has(event.rowId))||(event.table==='projects'&&!current.projects.some(p=>p.id===event.rowId)))portfolio.tableHistory.push(structuredClone(event));
    }
  }
  const report={added:importedIds.size,unchanged,conflicts};
  if(payload.tableColumns)Object.assign(report,{columnsAdded,projectsAdded});
  return { portfolio, report };
}
