import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { backupData } from '../lib/backup.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
console.log(JSON.stringify(backupData(process.env.DASHBOARD_DATA_DIR ?? path.join(root,'data'),{force:true}),null,2));
