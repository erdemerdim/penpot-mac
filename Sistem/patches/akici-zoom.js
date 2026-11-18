// Akıcı yakınlaştırma (proxy.mjs bu dosyayı Penpot sayfasına ekler).
//
// Sorun: macOS'un web motorunda (WKWebView) Cmd/Ctrl + kaydırma olayları seyrek ve büyük adımlarla
// geliyor (80–160 ms arayla, deltaY ±80–250). Penpot her olayda yakınlaştırmayı bir anda uyguladığı
// için hareket kesik kesik görünüyordu. Ayrıca trackpad'de iki parmakla yakınlaştırma (pinch)
// WebKit'te "gesture" olayı olarak geliyor ve Penpot bunu dinlemiyor.
//
// Çözüm: gerçek yakınlaştırma olaylarını yakalayıp birikimi her ekran karesine küçük parçalar hâlinde
// dağıtıyoruz (Figma gibi süzülerek yakınlaşma). Pinch hareketini de aynı yoldan Ctrl + kaydırmaya çeviriyoruz.
// Penpot'a giden olaylar normal "wheel" olaylarıdır; Penpot'un kodu değişmez.
(function () {
  if (window.__akiciZoom) return; window.__akiciZoom = true;
  const EASE = 0.28;        // her karede kalan yakınlaştırmanın ne kadarı uygulansın
  const MAX_STEP = 40;      // bir karede en fazla deltaY
  const PINCH_GAIN = 260;   // pinch ölçek değişimini deltaY'ye çevirme katsayısı
  let pending = 0, target = null, x = 0, y = 0, mods = { ctrlKey: true, metaKey: false }, running = false;

  const inCanvas = el => !!(el && el.closest && el.closest(".viewport, [class*='viewport'], canvas, svg.render-shapes"));

  function pump() {
    if (Math.abs(pending) < 0.4 || !target || !target.isConnected) { pending = 0; running = false; return; }
    let step = pending * EASE;
    if (Math.abs(step) < 1) step = Math.sign(pending) * Math.min(1, Math.abs(pending));
    step = Math.max(-MAX_STEP, Math.min(MAX_STEP, step));
    pending -= step;
    target.dispatchEvent(new WheelEvent("wheel", {
      deltaY: step, deltaX: 0, deltaMode: 0, clientX: x, clientY: y, screenX: x, screenY: y,
      ctrlKey: mods.ctrlKey, metaKey: mods.metaKey, bubbles: true, cancelable: true, composed: true, view: window,
    }));
    requestAnimationFrame(pump);
  }
  function feed(delta, el, cx, cy, m) {
    target = el; x = cx; y = cy; mods = m;
    // Yön değişirse eski birikimi bırak (anında tepki)
    if (pending && Math.sign(pending) !== Math.sign(delta)) pending = 0;
    pending += delta;
    if (!running) { running = true; requestAnimationFrame(pump); }
  }

  // Cmd/Ctrl + kaydırma (gerçek olaylar). Kendi ürettiğimiz olaylar isTrusted=false olduğu için yakalanmaz.
  window.addEventListener("wheel", e => {
    if (!e.isTrusted || !(e.ctrlKey || e.metaKey) || !inCanvas(e.target)) return;
    e.preventDefault(); e.stopImmediatePropagation();
    const d = e.deltaMode === 1 ? e.deltaY * 16 : e.deltaMode === 2 ? e.deltaY * 400 : e.deltaY;
    feed(d, e.target, e.clientX, e.clientY, { ctrlKey: e.ctrlKey, metaKey: e.metaKey });
  }, { capture: true, passive: false });

  // Trackpad pinch (WebKit gesture olayları)
  let lastScale = 1, gx = 0, gy = 0;
  window.addEventListener("mousemove", e => { gx = e.clientX; gy = e.clientY; }, { capture: true, passive: true });
  window.addEventListener("gesturestart", e => { lastScale = 1; e.preventDefault(); }, { capture: true, passive: false });
  window.addEventListener("gesturechange", e => {
    e.preventDefault();
    const el = document.elementFromPoint(gx, gy);
    if (!inCanvas(el)) { lastScale = e.scale; return; }
    const d = -Math.log(e.scale / lastScale) * PINCH_GAIN; lastScale = e.scale;
    if (d) feed(d, el, gx, gy, { ctrlKey: true, metaKey: false });
  }, { capture: true, passive: false });
  window.addEventListener("gestureend", e => e.preventDefault(), { capture: true, passive: false });
})();
