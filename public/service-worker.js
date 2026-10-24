const CACHE = 'indicators-work-offline-1.22.0-weekly-focus';
const OFFLINE = ['/art/monet-water-lilies-1906.jpg', '/offline.html', '/timer-ringtones.js', '/timer-ringtones.css', '/ringtones/catalog.json', '/ringtones/bip_bip.wav', '/ringtones/sonar.wav', '/ringtones/glass.wav', '/ringtones/marimba.wav', '/ringtones/orbit.wav', '/ringtones/warm_bell.wav', '/ringtones/classic.wav', '/offline-work.css', '/offline-work.js', '/focus-ambience.js', '/focus-youtube.js', '/focus-ambience.css', '/offline-store.js', '/offline-engine.js', '/timer-core.js', '/manifest.webmanifest', '/icon-192.png', '/icon-512.png', '/icon-maskable-512.png'];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(OFFLINE)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('indicators-work-offline-') && key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || url.pathname.startsWith('/api/')) return;
  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request).catch(() => caches.match('/offline.html')));
  } else if (OFFLINE.includes(url.pathname)) {
    event.respondWith(fetch(event.request).catch(() => caches.match(event.request)));
  }
});
