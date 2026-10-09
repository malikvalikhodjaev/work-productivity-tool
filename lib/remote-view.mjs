import http from 'node:http';
import { existsSync, readFileSync } from 'node:fs';

const readRoutes = new Set([
  '/api/health', '/api/references', '/api/today', '/api/daily-results',
  '/api/daily-problems', '/api/workspace', '/api/finance', '/api/dashboard',
  '/api/overview', '/api/indicator-ratings', '/api/portfolio', '/api/time-entries',
  '/api/alphas/export', '/api/alphas/history', '/api/imported-data',
  '/adr/time-sources', '/adr/work-loop',
]);

export function readRemoteConfig(file) {
  if (!existsSync(file)) return null;
  const value = JSON.parse(readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  const url = new URL(value.url);
  if (value.version !== 1 || url.protocol !== 'https:' || !/^[a-z0-9-]+\.[a-z0-9-]+\.ts\.net$/.test(url.hostname)
      || url.port || url.username || url.password || url.pathname !== '/' || url.search || url.hash
      || typeof value.allowedLogin !== 'string' || !value.allowedLogin.trim() || value.allowedLogin.length > 240) {
    throw new Error('Некорректная настройка закрытого доступа.');
  }
  return { url: url.origin, allowedLogin: value.allowedLogin.trim().toLowerCase() };
}

export function createRemoteViewer({ configFile, ownerPort, viewerPort, assetPaths }) {
  let listening = false;
  let startupError = false;
  const status = () => {
    try {
      const config = readRemoteConfig(configFile);
      return { mode: 'owner', configured: Boolean(config), gatewayReady: listening, gatewayError: startupError,
        url: config?.url ?? null, access: 'read-only', requiresComputer: true };
    } catch {
      return { mode: 'owner', configured: false, gatewayReady: listening, gatewayError: startupError,
        url: null, error: 'Настройка доступа повреждена. Запусти Connect-Android.ps1 повторно.' };
    }
  };
  const json = (res, code, value) => { res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(value)); };
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'same-origin');
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'self'; base-uri 'none'; form-action 'self'");
    try {
      const config = readRemoteConfig(configFile);
      if (!config) return json(res, 503, { error: 'Доступ с телефона пока не подключён.' });
      if (req.headers.host !== new URL(config.url).host
          || req.headers['tailscale-user-login']?.toLowerCase() !== config.allowedLogin) {
        return json(res, 403, { error: 'Открой адрес через Tailscale под аккаунтом владельца.' });
      }
      if (req.headers.origin && req.headers.origin !== config.url) return json(res, 403, { error: 'Запрос с другого сайта запрещён.' });
      if (!['GET', 'HEAD'].includes(req.method)) return json(res, 403, { error: 'На телефоне доступен просмотр. Изменения сохраняются на ПК.' });
      if (!req.url.startsWith('/') || req.url.startsWith('//')) return json(res, 404, { error: 'Страница не найдена.' });
      const url = new URL(req.url, config.url);
      if (url.pathname === '/api/mobile-access') return json(res, 200, { mode: 'viewer', configured: true, gatewayReady: true, url: config.url, access: 'read-only', requiresComputer: true });
      const attachment = /^\/api\/references\/[a-z0-9-]+\/attachment$/.test(url.pathname);
      if (!assetPaths.has(url.pathname) && !readRoutes.has(url.pathname) && !attachment) return json(res, 404, { error: 'Страница не найдена.' });
      const upstream = await fetch(`http://127.0.0.1:${ownerPort}${url.pathname}${url.search}`, { method: req.method, redirect: 'error', signal: AbortSignal.timeout(5000) });
      const contentType = upstream.headers.get('content-type') ?? 'application/octet-stream';
      res.statusCode = upstream.status;
      res.setHeader('Content-Type', contentType);
      if (url.pathname === '/service-worker.js') res.setHeader('Service-Worker-Allowed', '/');
      if (req.method === 'HEAD') return res.end();
      if (contentType.startsWith('text/html')) {
        const html = (await upstream.text()).replace('</head>', '<meta name="dashboard-access" content="viewer">\n</head>');
        return res.end(html);
      }
      res.end(Buffer.from(await upstream.arrayBuffer()));
    } catch {
      json(res, 503, { error: 'Нет соединения с дашбордом на ПК. Проверь, что компьютер включён и сервер работает.' });
    }
  });
  server.on('listening', () => { listening = true; startupError = false; });
  server.on('close', () => { listening = false; });
  server.on('error', error => { startupError = true; console.error(`Сервер просмотра: ${error.code ?? error.message}`); });
  return { server, status, start: () => server.listen(viewerPort, '127.0.0.1') };
}
