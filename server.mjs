import http from 'node:http';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { createStore } from './lib/store.mjs';
import { createIndicatorStore } from './lib/indicators.mjs';
import { createDailyProblemStore } from './lib/daily-problems.mjs';
import { createDailyResultStore } from './lib/daily-results.mjs';
import { createWorkspaceStore } from './lib/workspace.mjs';
import { parseFinanceCsv } from './lib/finance-csv.mjs';
import { createReferenceStore } from './lib/references.mjs';
import { createRemoteViewer } from './lib/remote-view.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.DASHBOARD_PORT ?? 8787);
const dataDir = process.env.DASHBOARD_DATA_DIR ?? path.join(root, 'data');
let store;
const workspace = createWorkspaceStore(path.join(dataDir, 'workspace.json'), () => store.getPortfolio());
store = createStore(process.env.DASHBOARD_DATA_FILE ?? path.join(dataDir, 'dashboard.json'), { validateWorkRef: workspace.validateRef });
const indicators = createIndicatorStore(path.join(dataDir, 'indicators.json'));
const dailyProblems = createDailyProblemStore(path.join(dataDir, 'daily-problems.json'));
const dailyResults = createDailyResultStore(path.join(dataDir, 'daily-results.json'), { validateWorkRef: workspace.validateRef });
const references = createReferenceStore(path.join(dataDir, 'references.json'));
const assets = { '/': ['index.html', 'text/html; charset=utf-8'], '/app.js': ['app.js', 'text/javascript; charset=utf-8'], '/projects.js': ['projects.js', 'text/javascript; charset=utf-8'], '/overview.js': ['overview.js', 'text/javascript; charset=utf-8'], '/styles.css': ['styles.css', 'text/css; charset=utf-8'], '/projects.css': ['projects.css', 'text/css; charset=utf-8'], '/favicon.svg': ['favicon.svg', 'image/svg+xml'] };
assets['/workspace.js'] = ['workspace.js', 'text/javascript; charset=utf-8'];
assets['/workspace.css'] = ['workspace.css', 'text/css; charset=utf-8'];
assets['/sections.css'] = ['sections.css', 'text/css; charset=utf-8'];
assets['/daily-problem.js'] = ['daily-problem.js', 'text/javascript; charset=utf-8'];
assets['/daily-problem.css'] = ['daily-problem.css', 'text/css; charset=utf-8'];
assets['/today.js'] = ['today.js', 'text/javascript; charset=utf-8'];
assets['/work.css'] = ['work.css', 'text/css; charset=utf-8'];
assets['/references.js'] = ['references.js', 'text/javascript; charset=utf-8'];
assets['/references.css'] = ['references.css', 'text/css; charset=utf-8'];
assets['/today.css'] = ['today.css', 'text/css; charset=utf-8'];
assets['/alphas'] = ['alphas.html', 'text/html; charset=utf-8'];
assets['/alphas.js'] = ['alphas.js', 'text/javascript; charset=utf-8'];
assets['/alphas.css'] = ['alphas.css', 'text/css; charset=utf-8'];
for (const [route, type] of [['/manifest.webmanifest','application/manifest+json'],['/service-worker.js','text/javascript; charset=utf-8'],['/mobile.js','text/javascript; charset=utf-8'],['/remote-view.js','text/javascript; charset=utf-8'],['/mobile.css','text/css; charset=utf-8'],['/offline.html','text/html; charset=utf-8'],['/offline.js','text/javascript; charset=utf-8'],['/icon-192.png','image/png'],['/icon-512.png','image/png'],['/icon-maskable-512.png','image/png']]) assets[route] = [route.slice(1), type];
const viewerPort = Number(process.env.DASHBOARD_VIEWER_PORT ?? 8789);
if (!Number.isInteger(viewerPort) || viewerPort < 1 || viewerPort > 65535 || viewerPort === port) throw new Error('DASHBOARD_VIEWER_PORT должен быть отдельным портом 1–65535.');
const remoteViewer = createRemoteViewer({ configFile: path.join(dataDir, 'remote-access.json'), ownerPort: port, viewerPort, assetPaths: new Set(Object.keys(assets)) });

function json(res, status, value) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(value));
}

async function body(req) {
  if (!req.headers['content-type']?.startsWith('application/json')) throw new Error('Нужен запрос в формате JSON.');
  const parts = [];
  let bytes = 0;
  for await (const part of req) {
    bytes += part.length;
    if (bytes > (['/api/finance/import', '/api/alphas/import'].includes(req.url) ? 4 * 1024 * 1024 : 65536)) throw new Error('Запрос слишком большой.');
    parts.push(part);
  }
  const value = JSON.parse(Buffer.concat(parts).toString('utf8'));
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Нужен объект JSON.');
  return value;
}

const server = http.createServer(async (req, res) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'same-origin');
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'self'; base-uri 'none'; form-action 'self'");
  const expectedHosts = [`127.0.0.1:${port}`, `localhost:${port}`];
  if (!expectedHosts.includes(req.headers.host)) return json(res, 403, { error: 'Доступ только с этого компьютера.' });
  if (req.headers.origin && !expectedHosts.some(host => req.headers.origin === `http://${host}`)) return json(res, 403, { error: 'Запрос с другого сайта запрещён.' });
  try {
    const url = new URL(req.url, `http://127.0.0.1:${port}`);
    if (req.method === 'GET' && url.pathname === '/api/health') return json(res, 200, { ok: true, service: 'rhythm-dashboard', version: '1.2.0', timezone: 'Asia/Tashkent' });
    if (req.method === 'GET' && url.pathname === '/api/mobile-access') return json(res, 200, remoteViewer.status());
    if (req.method === 'GET' && url.pathname === '/api/references') return json(res, 200, references.view());
    if (req.method === 'POST' && url.pathname === '/api/references') return json(res, 200, references.save(await body(req)));
    if (req.method === 'GET' && /^\/api\/references\/[a-z0-9-]+\/attachment$/.test(url.pathname)) {
      const file = references.attachment(url.pathname.split('/')[3]);
      if (!file) return json(res, 404, { error: 'No Data · локальное вложение не найдено.' });
      res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'no-cache' });
      return res.end(readFileSync(file));
    }
    if (req.method === 'GET' && url.pathname === '/api/today') {
      const date = url.searchParams.get('date');
      if (date && date > dailyResults.view().today) throw new Error('Выбери прошедшую или сегодняшнюю дату.');
      const snapshot = store.getToday(date ?? undefined);
      return json(res, 200, { ...snapshot, result: dailyResults.view().entries.find(item => item.date === snapshot.date) ?? null, problem: dailyProblems.view().entries.find(item => item.date === snapshot.date) ?? null });
    }
    if (req.method === 'GET' && url.pathname === '/api/daily-results') return json(res, 200, dailyResults.view());
    if (req.method === 'POST' && url.pathname === '/api/daily-results') return json(res, 200, dailyResults.save(await body(req)));
    if (req.method === 'GET' && url.pathname === '/api/daily-problems') return json(res, 200, dailyProblems.view());
    if (req.method === 'POST' && url.pathname === '/api/daily-problems') return json(res, 200, dailyProblems.save(await body(req)));
    if (req.method === 'GET' && url.pathname === '/api/workspace') return json(res, 200, workspace.view());
    if (req.method === 'POST' && url.pathname === '/api/workspace') { const value = await body(req); return json(res, 200, workspace.mutate(value.action, value.input)); }
    if (req.method === 'GET' && url.pathname === '/api/finance') {
      const period = store.getPeriod(url.searchParams.get('period') ?? '7d');
      return json(res, 200, workspace.finance(period.start, period.end));
    }
    if (req.method === 'POST' && url.pathname === '/api/finance/transactions') return json(res, 201, workspace.addTransaction(await body(req)));
    if (req.method === 'PATCH' && /^\/api\/finance\/transactions\/[^/]+$/.test(url.pathname)) return json(res, 200, workspace.correctTransaction(decodeURIComponent(url.pathname.split('/').at(-1)), await body(req)));
    if (req.method === 'POST' && url.pathname === '/api/finance/import') {
      const value = await body(req);
      return json(res, 200, workspace.importTransactions(parseFinanceCsv(value.csv), value.source, value.commit === true));
    }
    if (req.method === 'GET' && url.pathname === '/adr/time-sources') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-cache' });
      return res.end(readFileSync(path.join(root, 'docs', 'ADR-001-time-sources.md')));
    }
    if (req.method === 'GET' && url.pathname === '/adr/work-loop') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-cache' });
      return res.end(readFileSync(path.join(root, 'docs', 'ADR-002-personal-work-loop.md')));
    }
    if (req.method === 'GET' && url.pathname === '/api/dashboard') return json(res, 200, store.getWeek(url.searchParams.get('week') ?? undefined));
    if (req.method === 'GET' && url.pathname === '/api/overview') {
      const activity = store.getPeriod(url.searchParams.get('period') ?? '7d');
      return json(res, 200, { activity, assessment: indicators.getPeriod(activity.start, activity.end) });
    }
    if (req.method === 'GET' && url.pathname === '/api/indicator-ratings') return json(res, 200, indicators.getAll());
    if (req.method === 'POST' && url.pathname === '/api/indicator-ratings') return json(res, 200, indicators.rate(await body(req)));
    if (req.method === 'GET' && url.pathname === '/api/portfolio') return json(res, 200, store.getPortfolio());
    if (req.method === 'GET' && url.pathname === '/api/time-entries') return json(res, 200, store.getStoredEntries());
    if (req.method === 'GET' && url.pathname === '/api/alphas/export') return json(res, 200, store.alphaBackup());
    if (req.method === 'GET' && url.pathname === '/api/alphas/history') return json(res, 200, { entries: store.alphaHistory(url.searchParams.get('id')) });
    if (req.method === 'POST' && url.pathname === '/api/alphas/import') { const input = await body(req); return json(res, 200, store.importAlphas(input.backup, input.commit === true)); }
    if (req.method === 'GET' && url.pathname === '/api/imported-data') {
      const folder = path.join(dataDir, 'imports');
      const readOptional = (name, empty) => {
        const file = path.join(folder, name);
        return existsSync(file) ? { ...JSON.parse(readFileSync(file, 'utf8')), available: true } : { ...empty, available: false };
      };
      return json(res, 200, {
        snapshot: readOptional('coda-snapshot.json', { capturedAt: null, sources: {}, work: [], goals: [], issues: [] }),
        reference: readOptional('alpha-reference.json', { capturedAt: null, sources: {}, rows: [], roles: [], mistakes: [], actions: [], guidance: [], objectFields: [] })
      });
    }
    if (req.method === 'POST' && url.pathname === '/api/portfolio') {
      const input = await body(req);
      if (!input.input || typeof input.input !== 'object' || Array.isArray(input.input)) throw new Error('Укажи данные для сохранения.');
      return json(res, 200, store.updatePortfolio(input.action, input.input));
    }
    if (req.method === 'PUT' && url.pathname === '/api/targets') {
      const input = await body(req);
      if (typeof input.week !== 'string') throw new Error('Укажи неделю для нормативов.');
      return json(res, 200, store.updateTargets(input.week, input.targets));
    }
    if (req.method === 'POST' && url.pathname === '/api/entries') {
      const result = store.addEntry(await body(req));
      return json(res, result.duplicate ? 200 : 201, result);
    }
    if (req.method === 'PATCH' && /^\/api\/entries\/[^/]+$/.test(url.pathname)) return json(res, 200, store.classifyEntry(decodeURIComponent(url.pathname.split('/').at(-1)), await body(req)));
    if (req.method === 'DELETE' && /^\/api\/entries\/[a-f0-9-]{36}$/.test(url.pathname)) {
      const entry = store.removeEntry(url.pathname.split('/').at(-1));
      return json(res, 200, { removed: entry.id });
    }
    if ((req.method === 'GET' || req.method === 'HEAD') && assets[url.pathname]) {
      const [file, contentType] = assets[url.pathname];
      const content = readFileSync(path.join(root, 'public', file));
      res.writeHead(200, { 'Content-Type': contentType, 'Cache-Control': 'no-cache' });
      return res.end(req.method === 'HEAD' ? undefined : content);
    }
    json(res, 404, { error: 'Страница не найдена.' });
  } catch (error) {
    const systemError = error.code || (!(error instanceof SyntaxError) && /ENOENT|EACCES|EPERM/.test(error.message));
    if (systemError) console.error(error);
    json(res, systemError ? 500 : 400, { error: systemError ? 'Не удалось сохранить или прочитать данные. Повтори попытку.' : error instanceof SyntaxError ? 'Некорректный JSON.' : error.message });
  }
});
server.listen(port, '127.0.0.1', () => { remoteViewer.start(); console.log(`Indicators & Work Dashboard: http://127.0.0.1:${port}\nДанные: ${dataDir}\nПросмотр через Tailscale: 127.0.0.1:${viewerPort}`); });
server.on('error', error => { console.error(error.code === 'EADDRINUSE' ? `Порт ${port} занят. Открой http://127.0.0.1:${port} или задай DASHBOARD_PORT.` : error); process.exitCode = 1; });
