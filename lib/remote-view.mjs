import http from 'node:http';
import { existsSync, readFileSync } from 'node:fs';

const readRoutes = new Set([
  '/api/health', '/api/references', '/api/today', '/api/daily-results',
  '/api/daily-problems', '/api/workspace', '/api/finance', '/api/dashboard',
  '/api/overview', '/api/indicator-ratings', '/api/portfolio', '/api/time-entries',
  '/api/alphas/export', '/api/alphas/history', '/api/imported-data',
  '/adr/time-sources', '/adr/work-loop',
  '/api/timer', '/api/server-status',
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
  if (value.access !== undefined && !['read-only', 'read-write'].includes(value.access)) throw new Error('Некорректный режим закрытого доступа.');
  return { url: url.origin, allowedLogin: value.allowedLogin.trim().toLowerCase(), access: value.access ?? 'read-only' };
}

export function createRemoteViewer({ configFile, ownerPort, viewerPort, assetPaths }) {
  let listening = false;
  let startupError = false;
  const status = () => {
    try {
      const config = readRemoteConfig(configFile);
      return { mode: 'owner', configured: Boolean(config), gatewayReady: listening, gatewayError: startupError,
        provider: 'computer', url: config?.url ?? null, access: config?.access ?? 'read-only', requiresComputer: true };
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
      const write = !['GET', 'HEAD'].includes(req.method);
      if (write && config.access !== 'read-write') return json(res, 403, { error: 'На телефоне доступен просмотр. Изменения сохраняются на ПК.' });
      if (write && req.headers.origin !== config.url) return json(res, 403, { error: 'Для записи открой приложение по его закрытому адресу.' });
      if (!req.url.startsWith('/') || req.url.startsWith('//')) return json(res, 404, { error: 'Страница не найдена.' });
      const url = new URL(req.url, config.url);
      if (url.pathname === '/api/mobile-access') return json(res, 200, { mode: config.access === 'read-write' ? 'editor' : 'viewer', provider: 'computer', configured: true, gatewayReady: true, url: config.url, access: config.access, requiresComputer: true });
      const attachment = /^\/api\/references\/[a-z0-9-]+\/attachment$/.test(url.pathname);
      const writable = ['POST'].includes(req.method) && ['/api/offline/connect','/api/offline/import','/api/timer','/api/entries','/api/portfolio','/api/workspace','/api/daily-results','/api/daily-problems','/api/indicator-ratings','/api/references','/api/alphas/import','/api/finance/transactions','/api/finance/import'].includes(url.pathname)
        || req.method === 'PUT' && url.pathname === '/api/targets'
        || req.method === 'PATCH' && /^\/api\/(entries|finance\/transactions)\/[a-z0-9-]+$/.test(url.pathname)
        || req.method === 'DELETE' && /^\/api\/entries\/[a-f0-9-]{36}$/.test(url.pathname);
      if (write ? !writable : !assetPaths.has(url.pathname) && !readRoutes.has(url.pathname) && !attachment) return json(res, 404, { error: 'Страница не найдена.' });
      let payload;
      if (write) {
        if (req.method !== 'DELETE' && !req.headers['content-type']?.startsWith('application/json')) return json(res, 415, { error: 'Нужен JSON.' });
        const parts = []; let bytes = 0;
        for await (const part of req) { bytes += part.length; if (bytes > 4 * 1024 * 1024) return json(res, 413, { error: 'Запрос слишком большой.' }); parts.push(part); }
        payload = Buffer.concat(parts);
      }
      const upstream = await fetch(`http://127.0.0.1:${ownerPort}${url.pathname}${url.search}`, { method: req.method, ...(write ? { body: payload, headers: { 'Content-Type': 'application/json' } } : {}), redirect: 'error', signal: AbortSignal.timeout(10000) });
      const contentType = upstream.headers.get('content-type') ?? 'application/octet-stream';
      res.statusCode = upstream.status;
      res.setHeader('Content-Type', contentType);
      if (url.pathname === '/service-worker.js') res.setHeader('Service-Worker-Allowed', '/');
      if (req.method === 'HEAD') return res.end();
      if (contentType.startsWith('text/html')) {
        const html = config.access === 'read-only' ? (await upstream.text()).replace('</head>', '<meta name="dashboard-access" content="viewer">\n</head>') : await upstream.text();
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
  return { server, status, start: () => server.listen(viewerPort, process.env.DASHBOARD_GATEWAY_BIND ?? '127.0.0.1') };
}
