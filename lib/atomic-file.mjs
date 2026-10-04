import { renameSync } from 'node:fs';

export function replaceFile(source, target) {
  for (let attempt = 0; ; attempt++) {
    try { renameSync(source, target); return; }
    catch (error) {
      if (attempt >= 5 || !['EPERM', 'EACCES', 'EBUSY'].includes(error.code)) throw error;
      // Windows scanners can briefly lock the destination after a write.
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50 * (attempt + 1));
    }
  }
}
