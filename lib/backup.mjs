import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { replaceFile } from './atomic-file.mjs';

function sourceFiles(root, relative = '') {
  if (!existsSync(path.join(root, relative))) return [];
  return readdirSync(path.join(root, relative), { withFileTypes: true }).flatMap(item => {
    const name = path.join(relative, item.name);
    if (item.isSymbolicLink()) return [];
    if (item.isDirectory()) return ['imports', 'reference-assets'].includes(name.split(path.sep)[0]) ? sourceFiles(root, name) : [];
    return item.isFile() && /\.(json|png|csv)$/.test(name) ? [name] : [];
  }).sort();
}
export function backupStatus(dataDir) {
  const file = path.join(dataDir, 'backups', 'latest.json');
  if (!existsSync(file)) return { lastSuccess: null, fileCount: null };
  const value = JSON.parse(readFileSync(file, 'utf8'));
  return { lastSuccess: value.createdAt, fileCount: value.files.length, directory: value.directory };
}
export function backupData(dataDir, { now = new Date(), force = false } = {}) {
  const sources = sourceFiles(dataDir).map(name => {
    const bytes = readFileSync(path.join(dataDir, name));
    return { name: name.split(path.sep).join('/'), bytes, sha256: createHash('sha256').update(bytes).digest('hex') };
  });
  const files = sources.map(({ name, sha256, bytes }) => ({ name, sha256, size: bytes.length }));
  const parent = path.join(dataDir, 'backups');
  const latest = path.join(parent, 'latest.json');
  if (!force && existsSync(latest)) {
    const previous = JSON.parse(readFileSync(latest, 'utf8'));
    if (JSON.stringify(previous.files) === JSON.stringify(files)) return { ...backupStatus(dataDir), unchanged: true };
  }
  const directory = now.toISOString().replaceAll(':', '-').replaceAll('.', '-') + '-' + process.pid;
  const target = path.join(parent, directory);
  mkdirSync(target, { recursive: true });
  for (const source of sources) {
    const destination = path.join(target, source.name);
    mkdirSync(path.dirname(destination), { recursive: true });
    writeFileSync(destination, source.bytes);
    if (createHash('sha256').update(readFileSync(destination)).digest('hex') !== source.sha256) throw new Error('Не удалось проверить резервную копию.');
  }
  const manifest = { version: 1, createdAt: now.toISOString(), directory, files };
  writeFileSync(path.join(target, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  writeFileSync(latest + '.tmp', JSON.stringify(manifest, null, 2) + '\n');
  replaceFile(latest + '.tmp', latest);
  return { ...backupStatus(dataDir), unchanged: false };
}
