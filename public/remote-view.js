if (document.querySelector('meta[name="dashboard-access"][content="viewer"]')) {
  const cloud = Boolean(document.querySelector('meta[name="dashboard-hosting"][content="sites"]'));
  document.documentElement.classList.add('read-only-view');
  const mutations = '#targets-button,#entry-button,#new-project,#new-task,#new-alpha,#journal-add,#new,#import,#alpha-make-focus,#restore-draft,#discard-draft,#today-add-time,#source-add,[data-today-metric],[data-edit],[data-delete],[data-assess],[data-alpha-edit],[data-alpha-child],[data-alpha-task],[data-zone-slot],[data-task-toggle],[data-source-edit],[data-w-action]:not([data-w-action="table"]):not([data-w-action="link"]),button[type="submit"]';
  const enforce = () => {
    const label = document.getElementById('save-label');
    if (cloud && label && label.textContent !== 'Снимок сохранённых записей') label.textContent = 'Снимок сохранённых записей';
    document.querySelectorAll(mutations).forEach(element => { if (!element.disabled) element.disabled = true; element.classList.add('viewer-mutation'); });
    document.querySelectorAll('form input,form textarea,form select').forEach(element => {
      if (element.matches('textarea,input:not([type="checkbox"]):not([type="file"])')) { element.readOnly = true; if (!element.value) element.placeholder = 'No Data'; }
      else if (!element.disabled) element.disabled = true;
    });
    const resultState = document.getElementById('today-result-state');
    if (resultState && document.getElementById('today-result-status')?.textContent === 'No Data') {
      if (![...resultState.options].some(option => option.value === '')) resultState.prepend(new Option('No Data', ''));
      resultState.value = '';
    }
  };
  document.addEventListener('submit', event => { event.preventDefault(); event.stopImmediatePropagation(); }, true);
  document.addEventListener('click', event => {
    if (event.target.closest(mutations)) { event.preventDefault(); event.stopImmediatePropagation(); }
  }, true);
  window.addEventListener('keydown', event => {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') { event.preventDefault(); event.stopImmediatePropagation(); }
  }, true);
  document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.local-label,.local').forEach(element => { element.textContent = cloud ? 'Sites · Просмотр' : 'Просмотр · данные с ПК'; });
    document.querySelectorAll('.brand-sub,.brand small').forEach(element => { element.textContent = 'Личный дашборд · Просмотр'; });
    const mobile = document.getElementById('mobile-open'); if (mobile) mobile.textContent = 'Приложение ↗';
    if (!document.documentElement.classList.contains('embedded')) {
      const alert = document.createElement('p'); alert.className = 'viewer-connection-alert'; alert.hidden = true; alert.role = 'status';
      alert.textContent = cloud ? 'Нет связи с сервером. На открытой странице — последний загруженный снимок.' : 'Нет связи с ПК. На открытой странице — данные последнего обновления.';
      document.body.prepend(alert);
      if (cloud) {
        const info = document.createElement('p'); info.className = 'cloud-snapshot-info'; info.role = 'status'; info.textContent = 'Снимок данных · проверяю дату обновления…';
        info.title = 'Изменения на ПК не синхронизируются автоматически. Редактирование доступно в локальной версии.';
        document.body.prepend(info);
        fetch('/api/mobile-access', { cache: 'no-store' }).then(response => { if (!response.ok) throw new Error(); return response.json(); }).then(value => {
          const date = value.capturedAt ? new Intl.DateTimeFormat('ru-RU', { dateStyle: 'short', timeStyle: 'short', timeZone: 'Asia/Tashkent' }).format(new Date(value.capturedAt)) : 'No Data';
          info.textContent = `Снимок от ${date} · Только просмотр`;
        }).catch(() => { info.textContent = 'Дата снимка · No Data'; });
      }
      const checkConnection = async () => {
        if (document.visibilityState !== 'visible') return;
        try { const response = await fetch('/api/health', { cache: 'no-store', signal: AbortSignal.timeout(5000) }); alert.hidden = response.ok; }
        catch { alert.hidden = false; }
      };
      window.addEventListener('focus', checkConnection);
      document.addEventListener('visibilitychange', checkConnection);
      setInterval(checkConnection, 30000);
    }
    enforce();
    new MutationObserver(enforce).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['disabled'] });
  });
}
