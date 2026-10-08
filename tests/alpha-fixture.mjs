import { writeFileSync } from 'node:fs';
import { defaultZones } from '../lib/portfolio.mjs';

// A legacy portfolio without revisions exercises migration independently of user data.
export function writeLegacyAlphaFixture(file) {
  const at = '2026-10-05T08:00:00Z';
  const project = { id: 'test-project', name: 'Тестовый проект', status: 'active', phase: 'pre_operation', zones: structuredClone(defaultZones), createdAt: at, updatedAt: at };
  const alphas = defaultZones.map(zone => ({ id: `test-${zone.id}`, projectId: project.id, parentId: null, zoneId: zone.id, typeName: zone.typeName, uniqueName: `${zone.typeName} тестового проекта`, description: 'Исходная тестовая запись', state: 'empty', stateLabel: '', criteria: '', evidence: '', nextStep: '', filledDate: null, createdAt: at, updatedAt: at }));
  writeFileSync(file, JSON.stringify({ version: 1, plans: {}, entries: [], portfolio: { version: 1, projects: [project], tasks: [], alphas }, updatedAt: at }));
}
