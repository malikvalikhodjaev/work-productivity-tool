let installPrompt = null;
const viewer = Boolean(document.querySelector('meta[name="dashboard-access"][content="viewer"]'));
if ('serviceWorker' in navigator && window.isSecureContext) {
  window.addEventListener('load', () => navigator.serviceWorker.register('/service-worker.js').catch(() => {}));
}
window.addEventListener('beforeinstallprompt', event => {
  event.preventDefault(); installPrompt = event;
  const button = document.getElementById('mobile-install'); if (button) button.hidden = false;
});
window.addEventListener('appinstalled', () => { installPrompt = null; document.getElementById('mobile-install').hidden = true; });
document.addEventListener('DOMContentLoaded', () => {
  const dialog = document.createElement('dialog'); dialog.className = 'mobile-dialog'; dialog.id = 'mobile-dialog';
  dialog.innerHTML = `<button class="mobile-dialog-close" type="button" aria-label="Закрыть">×</button><p class="connection-eyebrow">INDICATORS &amp; WORK DASHBOARD</p><h2>${viewer ? 'Установить приложение' : 'Дашборд на Android'}</h2><p id="mobile-connection-status" class="connection-status" role="status">Проверяю подключение…</p><div id="mobile-connection-details"></div><button id="mobile-install" class="mobile-button" hidden>Установить на главный экран</button><p id="mobile-connection-note" class="connection-note"></p>`;
  document.body.append(dialog);
  dialog.querySelector('.mobile-dialog-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => { if (event.target === dialog) { const bounds = dialog.getBoundingClientRect(); if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close(); } });
  document.getElementById('mobile-install').addEventListener('click', async () => {
    if (!installPrompt) return;
    const prompt = installPrompt; installPrompt = null; await prompt.prompt();
    await prompt.userChoice; document.getElementById('mobile-install').hidden = true;
  });
  document.getElementById('mobile-open')?.addEventListener('click', async () => {
    dialog.showModal(); document.getElementById('mobile-install').hidden = !installPrompt;
    const status = document.getElementById('mobile-connection-status');
    const details = document.getElementById('mobile-connection-details'); details.replaceChildren();
    try {
      const response = await fetch('/api/mobile-access', { cache: 'no-store' }); const value = await response.json();
      if (!response.ok) throw new Error(value.error || 'Не удалось проверить доступ.');
      const note = document.getElementById('mobile-connection-note');
      if (value.provider === 'sites' && value.configured) {
        status.textContent = 'Закрытая веб-версия в Sites.';
        const link = document.createElement('a'); link.href = value.url; link.textContent = value.url; link.className = 'connection-address'; link.target = '_blank'; link.rel = 'noopener'; details.append(link);
        const steps = document.createElement('ol');
        steps.innerHTML = '<li>Открой ссылку в Chrome на Android и войди в свой аккаунт ChatGPT.</li><li>Нажми «Установить на главный экран» или меню Chrome → «Добавить на главный экран».</li><li>Открывай дашборд значком, как обычное приложение.</li>';
        details.append(steps);
        note.textContent = 'ПК может быть выключен. Доступен просмотр снимка данных; изменения на ПК пока не синхронизируются автоматически.';
      } else if (value.configured && value.gatewayReady) {
        note.textContent = 'На телефоне доступен просмотр. Компьютер должен быть включён, а Tailscale подключён на обоих устройствах.';
        status.textContent = viewer ? 'Открыта версия для просмотра.' : 'Закрытый HTTPS-адрес настроен. Проверка доступа — с телефона.';
        const link = document.createElement('a'); link.href = value.url; link.textContent = value.url; link.className = 'connection-address'; link.target = '_blank'; link.rel = 'noopener'; details.append(link);
        const steps = document.createElement('ol');
        steps.innerHTML = '<li>Подключи Tailscale на телефоне под тем же аккаунтом, что на ПК.</li><li>Открой этот адрес в Chrome.</li><li>Нажми «Установить на главный экран» или меню Chrome → «Добавить на главный экран» → «Установить».</li>';
        details.append(steps);
      } else {
        note.textContent = 'На телефоне доступен просмотр после подключения закрытого HTTPS-адреса.';
        status.textContent = value.error || (value.gatewayError ? 'Сервер просмотра не запустился. Проверь журнал сервера.' : 'Веб-приложение подготовлено. Закрытый доступ ещё не подключён.');
        const steps = document.createElement('ol');
        steps.innerHTML = '<li>Установи <a href="https://tailscale.com/download/windows" target="_blank" rel="noopener">Tailscale на ПК</a> и <a href="https://tailscale.com/download/android" target="_blank" rel="noopener">Android</a>. Войди в один аккаунт.</li><li>На ПК запусти <strong>Подключить Android.cmd</strong> из папки дашборда.</li><li>Здесь появится постоянный адрес для телефона.</li>';
        details.append(steps);
      }
    } catch (error) { status.textContent = error.message; }
  });
});
