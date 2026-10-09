import { existsSync, readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';
import { snapshotFiles, validateSnapshot } from '../lib/cloud-snapshot.mjs';

export function exportSnapshot(dataDir) {
  const folder=resolve(dataDir),files={};
  for(const name of snapshotFiles){const file=join(folder,name);if(existsSync(file))files[name]=readFileSync(file,'utf8');}
  const refs=JSON.parse(files['references.json']);const attachments=[],attachmentBytes={};
  for(const name of new Set(refs.entries.map(item=>item.attachment).filter(Boolean))){
    if(!/^[a-z0-9-]+\.png$/.test(name))throw new Error('Неверное имя вложения.');
    const path=`reference-assets/${name}`,file=join(folder,path);if(!existsSync(file))continue;
    const value=readFileSync(file);attachments.push({path,size:value.length,sha256:createHash('sha256').update(value).digest('hex')});attachmentBytes[path]=value.toString('base64');
  }
  const snapshot={format:'indicators-work-snapshot',version:1,capturedAt:new Date().toISOString(),files,attachments};
  validateSnapshot(snapshot);return {snapshot,attachmentBytes};
}
