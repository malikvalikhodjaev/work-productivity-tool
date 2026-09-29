// Запускать только в консоли инструментов разработчика самого Focus To-Do.
// Читает локальную IndexedDB без изменений и сохраняет JSON на компьютер.
(async () => {
  const database = await new Promise((resolve, reject) => {
    const request = indexedDB.open('PomodoroDB');
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
    request.onupgradeneeded = () => {
      request.transaction.abort();
      reject(new Error('База PomodoroDB не найдена в этом профиле приложения.'));
    };
  });

  const tables = {};
  for (const name of ['Project', 'Task', 'Pomodoro']) {
    if (!database.objectStoreNames.contains(name)) {
      tables[name] = [];
      continue;
    }
    tables[name] = await new Promise((resolve, reject) => {
      const transaction = database.transaction(name, 'readonly');
      const request = transaction.objectStore(name).getAll();
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
      transaction.onerror = () => reject(transaction.error);
    });
  }
  database.close();

  const content = JSON.stringify({ exportedAt: new Date().toISOString(), tables }, null, 2);
  const url = URL.createObjectURL(new Blob([content], { type: 'application/json' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = 'focus-to-do-data.json';
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
  console.table(Object.fromEntries(Object.entries(tables).map(([name, rows]) => [name, rows.length])));
})().catch(error => console.error('Не удалось выгрузить Focus To-Do:', error));
