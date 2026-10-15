import { createHash } from 'node:crypto';

export const nativeId = value => typeof value === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(value);
const canonical = value => JSON.stringify(value && typeof value === 'object' ? Array.isArray(value) ? value.map(v => JSON.parse(canonical(v))) : Object.fromEntries(Object.keys(value).sort().map(k => [k, JSON.parse(canonical(value[k]))])) : value);
export const nativeCommandSignature = command => createHash('sha256').update(canonical(command)).digest('hex');
export function nativeCommandGuard(getData) {
  let pending = null;
  const signature = nativeCommandSignature;
  const fail = message => { const error = new Error(message); error.status = 409; throw error; };
  function run(command, execute) {
    if (!command || !nativeId(command.requestId)) throw new Error('Нужен устойчивый UUID команды приложения.');
    const hash = signature(command);
    const receipt = getData().nativeRequests?.find(r => r.id === command.requestId);
    if (receipt) {
      if (receipt.hash !== hash) fail('UUID команды уже использован для других данных. Локальная запись сохранена.');
      return { duplicate: true };
    }
    if (pending) throw new Error('Вложенная команда приложения запрещена.');
    pending = { id: command.requestId, hash, at: new Date().toISOString() };
    try { execute(); return { duplicate: false }; }
    finally { pending = null; }
  }
  function prepare(next) {
    if (!pending) return next;
    if (next.nativeRequests?.some(r => r.id === pending.id)) return next;
    return { ...next, nativeRequests: [...(next.nativeRequests ?? []), { ...pending }] };
  }
  return { run, prepare };
}

export function assertNativeBase(previous, expected) {
  if (expected !== (previous?.updatedAt ?? null)) {
    const error = new Error('Данные изменились на другом устройстве. Локальная правка сохранена для разбора.');
    error.status = 409;
    throw error;
  }
}
