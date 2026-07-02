/* ============================================================
   Seven Store — Service Worker v2.0
   Strategy: Cache First for static assets, Network First for pages
   NOTE: Uses relative paths (no leading "/") so this works correctly
   both at a domain root and under a GitHub Pages project subpath
   (e.g. username.github.io/repo-name/).
============================================================ */

const CACHE_NAME     = 'sevenstore-v4';
const RUNTIME_CACHE  = 'sevenstore-runtime-v3';

/* Resolve precache URLs relative to this service worker's own location,
   so the same file works whether deployed at a root domain or under
   a GitHub Pages project subpath. */
const PRECACHE_ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './assets/js/cart.js',
  './assets/js/supabase-client.js',
  './assets/images/logo-512.webp',
  './assets/images/logo-nav-light.webp',
  './assets/images/logo-nav-dark.webp',
  './assets/images/icon-192.png',
  './assets/images/icon-512.png'
].map(path => new URL(path, self.registration.scope).toString());

/* ── Install: pre-cache shell ── */
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(PRECACHE_ASSETS))
      .catch(err => console.log('SW precache failed:', err))
  );
  self.skipWaiting();
});

/* ── Activate: clean up old caches ── */
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys
          .filter(k => k !== CACHE_NAME && k !== RUNTIME_CACHE)
          .map(k => caches.delete(k))
      )
    )
  );
  self.clients.claim();
});

/* ── Fetch: Stale-While-Revalidate for same-origin, passthrough for CDN ── */
self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  /* Skip non-GET & non-http(s) */
  if (request.method !== 'GET' || !request.url.startsWith('http')) return;

  /* Network-only for WhatsApp / external APIs */
  if (!url.origin.includes(self.location.origin) &&
      !url.hostname.includes('fonts.googleapis.com') &&
      !url.hostname.includes('fonts.gstatic.com') &&
      !url.hostname.includes('cdnjs.cloudflare.com')) return;

  /* Stale-While-Revalidate */
  event.respondWith(
    caches.open(RUNTIME_CACHE).then(cache =>
      cache.match(request).then(cached => {
        const networkFetch = fetch(request)
          .then(response => {
            if (response && response.status === 200 && response.type === 'basic') {
              cache.put(request, response.clone());
            }
            return response;
          })
          .catch(() => cached);
        return cached || networkFetch;
      })
    )
  );
});
