// Actualización automática: al abrir la app (o volver a ella) compara la versión
// publicada con la que está corriendo; si hay una nueva, recarga una sola vez.
(function () {
  var BUILD = '__BUILD_ID__';
  function check() {
    fetch('build_id.txt?t=' + Date.now(), { cache: 'no-store' })
      .then(function (r) { return r.text(); })
      .then(function (t) {
        t = (t || '').trim();
        if (!t || t === BUILD) return;
        try {
          if (sessionStorage.getItem('nj_reloaded') === t) return;
          sessionStorage.setItem('nj_reloaded', t);
        } catch (e) {}
        var jobs = [];
        if ('serviceWorker' in navigator) {
          jobs.push(navigator.serviceWorker.getRegistrations().then(function (rs) {
            return Promise.all(rs.map(function (r) { return r.unregister(); }));
          }));
        }
        if (window.caches) {
          jobs.push(caches.keys().then(function (ks) {
            return Promise.all(ks.map(function (k) { return caches.delete(k); }));
          }));
        }
        var go = function () { location.replace(location.pathname + '?v=' + t); };
        Promise.all(jobs).then(go, go);
      })
      .catch(function () {});
  }
  setTimeout(check, 2500);
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) check();
  });
})();
