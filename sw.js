// Mode hors-ligne : l'app s'ouvre même sans réseau (les chantiers restent enregistrés sur l'appareil
// et partent dans Supabase au retour du réseau). Changer VERSION à chaque mise en ligne.
const VERSION = 'emargement-v1';
const FICHIERS = [
  './', './index.html', './logos.js', './manifest.webmanifest',
  './assets/logo-wordmark.png', './assets/monogram.png', './assets/icone-192.png', './assets/icone-512.png',
  'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js',
];

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(caches.open(VERSION).then(c => Promise.allSettled(FICHIERS.map(f => c.add(f)))));
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(cles => Promise.all(cles.filter(k => k !== VERSION).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== 'GET') return;
  // Supabase, Gmail et la page de signature du client passent toujours par le réseau.
  if (url.hostname.endsWith('supabase.co') || url.hostname.endsWith('workers.dev') || url.pathname.endsWith('signer.html')) return;
  const memorisable = url.origin === location.origin || url.hostname === 'cdnjs.cloudflare.com' || url.hostname.endsWith('gstatic.com') || url.hostname.endsWith('googleapis.com');
  if (!memorisable) return;
  if (req.mode === 'navigate') {
    // Page de l'app : la version en ligne d'abord, celle de l'appareil si pas de réseau.
    e.respondWith(fetch(req).then(r => { const copie = r.clone(); caches.open(VERSION).then(c => c.put(req, copie)); return r; })
      .catch(() => caches.match(req).then(r => r || caches.match('./index.html'))));
    return;
  }
  e.respondWith(caches.match(req).then(enCache => enCache || fetch(req).then(r => {
    if (r.ok || r.type === 'opaque') { const copie = r.clone(); caches.open(VERSION).then(c => c.put(req, copie)); }
    return r;
  })));
});
