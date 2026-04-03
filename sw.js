const CACHE_NAME = 'sabor-v3';

const PRECACHE_URLS = [
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  'https://cdnjs.cloudflare.com/ajax/libs/react/18.2.0/umd/react.development.js',
  'https://cdnjs.cloudflare.com/ajax/libs/react-dom/18.2.0/umd/react-dom.development.js',
  'https://cdnjs.cloudflare.com/ajax/libs/babel-standalone/7.23.2/babel.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet.markercluster/1.5.3/leaflet.markercluster.js',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2'
];

// Network-first domains (never serve stale data for these)
const NETWORK_FIRST_PATTERNS = [
  'supabase.co',
  'googleapis.com',
  'maps.googleapis.com',
  'places.googleapis.com',
  // Always fetch fresh HTML so deploys take effect immediately
  '/index.html',
  'index.html'
];

function isNetworkFirst(url) {
  return NETWORK_FIRST_PATTERNS.some(pattern => url.includes(pattern));
}

// Install: precache core assets
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(PRECACHE_URLS))
      .then(() => self.skipWaiting())
  );
});

// Activate: clean old caches
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

// Fetch: Cache First for static, Network First for APIs and HTML
self.addEventListener('fetch', event => {
  const { request } = event;

  // Skip non-GET requests
  if (request.method !== 'GET') return;

  // Network First for Supabase, Google Places, and HTML
  if (isNetworkFirst(request.url)) {
    event.respondWith(
      fetch(request)
        .then(response => {
          // Don't cache auth or API responses
          return response;
        })
        .catch(() => caches.match(request))
    );
    return;
  }

  // Cache First for everything else
  event.respondWith(
    caches.match(request)
      .then(cached => {
        if (cached) return cached;
        return fetch(request).then(response => {
          // Cache successful responses for static assets
          if (response.ok && (request.url.startsWith('http'))) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(request, clone));
          }
          return response;
        });
      })
  );
});
