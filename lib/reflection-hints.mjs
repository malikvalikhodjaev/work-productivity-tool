import {existsSync, readFileSync} from 'node:fs';
import {join} from 'node:path';

const sourceKeys = ['feynman', 'oz', 'lift', 'musk', 'muskOriginal', 'done'];
const read = file => {
  try { const value=existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {}; return value && typeof value==='object' && !Array.isArray(value) ? value : {}; }
  catch { return {}; }
};
const safeAddress = value => {
  if (typeof value !== 'string' || value.length > 3000) return null;
  try {
    const url = new URL(value);
    return ['http:', 'https:'].includes(url.protocol) && !url.username && !url.password ? value : null;
  } catch { return null; }
};

// Personal source addresses remain in private data, outside the public checkout.
export function readReflectionHints(dataDir) {
  const config = read(join(dataDir, 'reflection-hints.json'));
  const writing = read(join(dataDir, 'writing-hints.json'));
  const sources = {};
  for (const key of sourceKeys) {
    const url = safeAddress(config.sources?.[key]?.url) ?? (key === 'feynman' ? safeAddress(writing.url) : null);
    if (url) sources[key] = {url};
  }
  const doneQuote = typeof config.doneQuote === 'string' && config.doneQuote.trim() && config.doneQuote.length <= 200 ? config.doneQuote.trim() : null;
  return {sources, doneQuote};
}
