import { timerState, timerSettings, changeTimer } from './timer-core.js';

export function createDeviceStore(factory = globalThis.indexedDB, name = 'indicators-work-device-v1') {
  let dbPromise;
  const open = () => dbPromise ??= new Promise((resolve, reject) => {
    const request = factory.open(name, 1);
    request.onupgradeneeded = () => request.result.createObjectStore('state');
    request.onsuccess = () => { const db = request.result; db.onversionchange = () => { db.close(); dbPromise = null; }; resolve(db); };
    request.onerror = () => reject(request.error);
    request.onblocked = () => reject(new Error('Закрой другие вкладки приложения и повтори.'));
  });
  async function update(change) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('state', 'readwrite'), store = tx.objectStore('state');
      let result, error;
      const request = store.get('device');
      request.onsuccess = () => {
        try {
          const state = request.result ?? { version: 1, deviceId: crypto.randomUUID(), revision: 0, timer: timerState(), context: null, queue: {}, lastClock: 0 };
          if (state.version !== 1) throw new Error('Неподдерживаемые локальные данные. Исходник сохранён.');
          change(state); state.revision++; store.put(state, 'device'); result = structuredClone(state);
        } catch (e) { error = e; tx.abort(); }
      };
      tx.oncomplete = () => resolve(result);
      tx.onabort = tx.onerror = () => reject(error ?? tx.error ?? new Error('Не удалось сохранить на устройстве.'));
    });
  }
  async function read() {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('state', 'readonly'), r = tx.objectStore('state').get('device');
      r.onsuccess = () => resolve(r.result ?? null); r.onerror = () => reject(r.error);
    });
  }
  async function action(action, input = {}, expectedRevision, now = Date.now()) {
    return update(state => {
      if (!state.context) throw new Error('Сначала подключи устройство к серверу.');
      if (state.timer.revision !== expectedRevision) throw new Error('Сеанс изменён в другой вкладке. Обнови страницу.');
      if (now < state.lastClock) throw new Error('Часы устройства переведены назад. Исправь системное время; сеанс сохранён.');
      const result = changeTimer(state.timer, action, { ...input, requestId: crypto.randomUUID(), expectedRevision }, {
        now, metrics: state.context.metrics,
        validateWorkRef: ref => { if (!ref) return null; if (!state.context.entities.some(e => e.ref === ref)) throw new Error('Выбери работу из сохранённого списка.'); return ref; }
      });
      if (['start','startBreak'].includes(action) && input.settings) result.timer.settings = timerSettings(input.settings);
      state.timer = result.timer; state.lastClock = now;
      if (['finish','cancel'].includes(action)) {
        const session = result.timer.sessions.find(s => s.id === input.sessionId);
        state.queue[session.id] = { status: 'pending', session: structuredClone(session), serverId: state.context.serverId, createdAt: new Date(now).toISOString() };
      }
    });
  }
  return { read, update, action, close: async () => { (await open()).close(); dbPromise = null; } };
}
