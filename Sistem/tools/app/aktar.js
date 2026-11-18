// Penpot.app: Penpot panosunun sol menüsüne "Figma'da aç" / "Illustrator'da aç" kartlarını ekler.
// Penpot'un kendi koduna dokunmaz; Penpot.app bu dosyayı sayfaya kullanıcı betiği olarak yükler.
//
// Akış: kart -> dosya seçimi (takımın projeleri) -> çalışma alanı (board) seçimi -> Penpot'un
// kendi dışa aktarıcısıyla (/api/export) her board PDF (Illustrator) ya da SVG (Figma) olarak alınır
// -> uygulamaya (Swift, penpotAktar) gönderilir -> PDF'ler birleştirilip Illustrator'da açılır /
// SVG'ler tek tasarımda birleştirilip panoya kopyalanır ve Figma açılır.
//
// Tutunma noktası: [data-testid="pinned-projects"] (Penpot sol menüsündeki "Sabitlenen projeler").
// Penpot güncellenip bu işaret değişirse kartlar görünmez; Penpot yine normal çalışır.
(function () {
  if (window.__ppxAktar) return;
  window.__ppxAktar = true;
  const ROOT_ID = "00000000-0000-0000-0000-000000000000";

  // ------------------------------------------------------------------ yardımcılar
  const el = (tag, attrs = {}, ...kids) => {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (k === "class") n.className = v;
      else if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
      else if (k === "html") n.innerHTML = v;
      else n.setAttribute(k, v);
    }
    for (const c of kids.flat()) if (c != null) n.append(c.nodeType ? c : document.createTextNode(String(c)));
    return n;
  };
  const rpc = async (cmd, body = {}) => {
    const r = await fetch("/api/rpc/command/" + cmd, {
      method: "POST", credentials: "include",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify(body),
    });
    if (!r.ok) throw new Error(cmd + " başarısız (" + r.status + ")");
    return r.json();
  };
  // Dışa aktarıcı transit+json bekler: anahtarlar "~:ad", uuid "~u...", anahtar sözcük "~:x"
  const tUuid = (s) => "~u" + s, tKw = (s) => "~:" + s;
  const untransit = (v) => {
    if (Array.isArray(v)) {
      if (v[0] === "^ ") { const o = {}; for (let i = 1; i < v.length; i += 2) o[untransit(v[i])] = untransit(v[i + 1]); return o; }
      return v.map(untransit);
    }
    if (v && typeof v === "object") {
      // Etiketli değer: {"~#uri": "http://..."} gibi -> içindeki değer
      const ks = Object.keys(v);
      if (ks.length === 1 && ks[0].startsWith("~#")) return untransit(v[ks[0]]);
      const o = {}; for (const [k, x] of Object.entries(v)) o[untransit(k)] = untransit(x); return o; }
    if (typeof v === "string" && /^~[:ur]/.test(v)) return v.slice(2);
    return v;
  };
  const exportOne = async (profileId, fileId, pageId, board, type) => {
    const body = {
      "~:cmd": tKw("export-shapes"), "~:wait": true, "~:profile-id": tUuid(profileId),
      "~:exports": [{
        "~:file-id": tUuid(fileId), "~:page-id": tUuid(pageId), "~:object-id": tUuid(board.id),
        "~:type": tKw(type), "~:suffix": "", "~:scale": 1, "~:name": board.name,
      }],
    };
    const r = await fetch("/api/export", {
      method: "POST", credentials: "include",
      headers: { "content-type": "application/transit+json", accept: "application/transit+json" },
      body: JSON.stringify(body),
    });
    if (!r.ok) throw new Error("Dışa aktarma başarısız (" + r.status + ")");
    const res = untransit(await r.json());
    let uri = res.uri || res["resource-uri"];
    if (typeof uri !== "string" && res.id) uri = "/assets/by-id/" + res.id;
    if (typeof uri !== "string") throw new Error("Dışa aktarıcı dosya adresi döndürmedi");
    // Sunucunun genel adresi yerine bu sayfanın adresini kullan (aynı yer, çerezler geçerli)
    try { const u = new URL(uri, location.href); uri = u.pathname + u.search; } catch (e) {}
    const f = await fetch(uri, { credentials: "include" });
    if (!f.ok) throw new Error("Dışa aktarılan dosya alınamadı (" + f.status + ")");
    if (type === "svg") {
      const text = await f.text();
      if (!/^\s*(<\?xml[^>]*>\s*)?(<!--[\s\S]*?-->\s*)*<svg[\s>]/i.test(text)) throw new Error(board.name + ": SVG beklenirken başka bir yanıt geldi");
      return text;
    }
    const blob = await f.blob();
    const head = new Uint8Array(await blob.slice(0, 5).arrayBuffer());
    if (String.fromCharCode(...head) !== "%PDF-") throw new Error(board.name + ": PDF beklenirken başka bir yanıt geldi");
    return await blobToBase64(blob);
  };
  const blobToBase64 = (blob) => new Promise((ok, fail) => {
    const fr = new FileReader();
    fr.onload = () => ok(String(fr.result).split(",")[1]);
    fr.onerror = () => fail(fr.error);
    fr.readAsDataURL(blob);
  });
  // Penpot'un SVG'si görselleri ve yazı tiplerini kendi adresine (localhost) bağlantı olarak verir;
  // Figma ve Illustrator bu adrese ulaşamaz. Görseller veri olarak gömülür, @font-face kuralları
  // kaldırılır (uygulamalar yazı tipini Mac'te kurulu olandan adıyla bulur).
  // WebP gibi biçimleri Illustrator SVG içinde okuyamayabilir: saydam görseller PNG'ye,
  // saydam olmayanlar JPEG'e çevrilir. PNG/JPEG/SVG olduğu gibi kalır.
  const blobToDataURL = (blob) => new Promise((ok, fail) => {
    const fr = new FileReader(); fr.onload = () => ok(fr.result); fr.onerror = () => fail(fr.error); fr.readAsDataURL(blob);
  });
  const toCompatibleDataURL = async (blob) => {
    if (/^image\/(png|jpeg|svg\+xml)$/.test(blob.type)) return blobToDataURL(blob);
    try {
      const bmp = await createImageBitmap(blob);
      const c = document.createElement("canvas"); c.width = bmp.width; c.height = bmp.height;
      const ctx = c.getContext("2d"); ctx.drawImage(bmp, 0, 0);
      let opaque = true;
      const px = ctx.getImageData(0, 0, c.width, c.height).data;
      for (let k = 3; k < px.length; k += 4 * 7) { if (px[k] < 255) { opaque = false; break; } }
      return c.toDataURL(opaque ? "image/jpeg" : "image/png", 0.92);
    } catch (e) { return blobToDataURL(blob); }   // çevrilemezse olduğu gibi
  };
  const inlineAssets = async (svg, onProgress) => {
    svg = svg.replace(/@font-face\s*\{[^}]*\}/g, "");
    const re = /(href|xlink:href)="((?:https?:\/\/[^"\/]+)?\/(?:assets|internal)\/[^"]+)"/g;
    const urls = [...new Set([...svg.matchAll(re)].map((m) => m[2]))];
    const data = {};
    for (let i = 0; i < urls.length; i++) {
      onProgress && onProgress(i + 1, urls.length);
      const u = new URL(urls[i].replace(/&amp;/g, "&"), location.href);
      const r = await fetch(u.pathname + u.search, { credentials: "include" });
      if (!r.ok) throw new Error("Görsel alınamadı (" + r.status + ")");
      data[urls[i]] = await toCompatibleDataURL(await r.blob());
    }
    return svg.replace(re, (m, attr, url) => `${attr}="${data[url] || url}"`);
  };
  const native = (msg) => window.webkit.messageHandlers.penpotAktar.postMessage(msg);
  const log = (m) => { try { window.webkit.messageHandlers.penpotApp.postMessage({ kind: "aktar", msg: String(m) }); } catch (e) {} };
  const currentTeamId = () => (location.hash.match(/team-id=([0-9a-f-]{36})/) || [])[1];
  const fmtDate = (s) => { try { return new Date(s).toLocaleDateString("tr-TR", { day: "numeric", month: "short", year: "numeric" }); } catch (e) { return ""; } };

  // ------------------------------------------------------------------ SVG'yi Figma/Illustrator'a uygun hâle getirme
  // Penpot'un SVG'si tarayıcıda doğru görünür ama Figma ve Illustrator'ın desteklemediği yapılar kullanır.
  // prepareSvg belgeyi bir kez okur ve sırayla düzeltir:
  //  1) Görsel dolgular: <pattern><image/></pattern> + fill="url(#…)" -> şekle kırpılmış gerçek <image>
  //  2) Maskeler: Penpot maske şeklini bir filtreyle beyaza boyar; Figma/Illustrator filtreyi uygulamaz,
  //     siyah/gri maske içeriği gizler -> mümkünse clip-path'e çevrilir, değilse maske şekli beyaz yapılır
  //  3) Yazılar: dominant-baseline="ideographic" yok sayılınca yazılar kayar -> konum tarayıcıda
  //     ölçülüp normal (alfabetik) taban çizgisine göre yazılır; textLength kaldırılır;
  //     "sans-serif, sourcesanspro" gibi listede gerçek yazı tipi öne alınır
  //  4) Katmanlar: etkisiz gruplar açılır, katmanlara Penpot'taki adlar verilir (id özniteliği)
  //  5) Görsel adresleri: Illustrator yalnızca xlink:href okur -> href yerine xlink:href yazılır
  const SVGNS = "http://www.w3.org/2000/svg", XLINK = "http://www.w3.org/1999/xlink";
  const IDENTITY = /^\s*matrix\(\s*1(\.0+)?\s*,\s*0(\.0+)?\s*,\s*0(\.0+)?\s*,\s*1(\.0+)?\s*,\s*0(\.0+)?\s*,\s*0(\.0+)?\s*\)\s*$/;
  const GEOMETRY = new Set(["rect", "path", "circle", "ellipse", "polygon", "polyline", "line"]);
  const urlId = (v) => ((v || "").match(/url\(#([^)]+)\)/) || [])[1];

  function flattenImagePatterns(doc) {
    const patterns = {};
    for (const p of doc.getElementsByTagNameNS(SVGNS, "pattern")) {
      const imgs = p.getElementsByTagNameNS(SVGNS, "image");
      if (imgs.length === 1 && (p.getAttribute("patternUnits") || "") === "userSpaceOnUse" && !p.getAttribute("patternTransform")) patterns[p.id] = p;
    }
    let n = 0;
    for (const shape of Array.from(doc.querySelectorAll("[fill^='url(#']"))) {
      const pat = patterns[urlId(shape.getAttribute("fill"))];
      if (!pat) continue;
      const img0 = pat.getElementsByTagNameNS(SVGNS, "image")[0];
      const px = parseFloat(pat.getAttribute("x") || 0), py = parseFloat(pat.getAttribute("y") || 0);
      const img = doc.createElementNS(SVGNS, "image");
      const href = img0.getAttribute("href") || img0.getAttributeNS(XLINK, "href");
      if (href) img.setAttribute("href", href);
      for (const at of ["preserveAspectRatio", "opacity"]) if (img0.getAttribute(at) != null) img.setAttribute(at, img0.getAttribute(at));
      img.setAttribute("x", px + parseFloat(img0.getAttribute("x") || 0));
      img.setAttribute("y", py + parseFloat(img0.getAttribute("y") || 0));
      img.setAttribute("width", img0.getAttribute("width") || pat.getAttribute("width"));
      img.setAttribute("height", img0.getAttribute("height") || pat.getAttribute("height"));
      const clip = doc.createElementNS(SVGNS, "clipPath");
      clip.id = "ppx-clip-" + (++n);
      const geo = shape.cloneNode(false);
      const tr = geo.getAttribute("transform"); geo.removeAttribute("transform");
      for (const at of ["fill", "fill-opacity", "style", "id", "class"]) geo.removeAttribute(at);
      clip.appendChild(geo);
      const g = doc.createElementNS(SVGNS, "g");
      if (tr && !IDENTITY.test(tr)) g.setAttribute("transform", tr);
      g.setAttribute("clip-path", `url(#${clip.id})`);
      const fo = shape.getAttribute("fill-opacity") || shape.getAttribute("opacity");
      if (fo && parseFloat(fo) !== 1) g.setAttribute("opacity", fo);
      g.appendChild(clip);
      g.appendChild(img);
      shape.replaceWith(g);
      pat.__ppxUsed = true;
    }
    for (const [id, pat] of Object.entries(patterns)) {
      if (pat.__ppxUsed && !doc.querySelector(`[fill="url(#${id.replace(/["\\]/g, "\\$&")})"]`)) pat.remove();
    }
  }

  function fixMasks(doc) {
    let clips = 0, whites = 0;
    for (const mask of Array.from(doc.getElementsByTagNameNS(SVGNS, "mask"))) {
      // Maskenin içindeki boyama filtresini kaldır, şekilleri beyaz yap (beyaz = tamamen görünür)
      for (const e of mask.querySelectorAll("[filter]")) e.removeAttribute("filter");
      const leaves = Array.from(mask.querySelectorAll("*")).filter((e) => GEOMETRY.has(e.localName));
      for (const e of leaves) {
        e.setAttribute("fill", "#ffffff"); e.removeAttribute("fill-opacity");
        const st = e.getAttribute("style");
        if (st) e.setAttribute("style", st.replace(/(^|;)\s*fill(-opacity)?\s*:[^;]*/g, "").replace(/^;+/, ""));
      }
      // Ara grupların hepsi etkisizse (dönüşüm yok) maske clip-path'e çevrilir: en geniş destek
      const simple = leaves.length > 0 && leaves.every((e) => {
        for (let p = e.parentElement; p && p !== mask; p = p.parentElement) {
          const t = p.getAttribute("transform");
          if ((t && !IDENTITY.test(t)) || p.getAttribute("clip-path") || p.getAttribute("mask") || p.getAttribute("opacity")) return false;
        }
        return true;
      });
      if (!simple) { whites++; continue; }
      const clip = doc.createElementNS(SVGNS, "clipPath");
      clip.id = mask.id + "-ppxclip";
      for (const e of leaves) {
        const c = e.cloneNode(false);
        for (const at of ["fill", "style", "id", "class", "stroke", "stroke-width"]) c.removeAttribute(at);
        if (IDENTITY.test(c.getAttribute("transform") || "")) c.removeAttribute("transform");
        clip.appendChild(c);
      }
      mask.parentNode.insertBefore(clip, mask);
      for (const user of Array.from(doc.querySelectorAll(`[mask="url(#${mask.id})"]`))) {
        user.removeAttribute("mask");
        if (user.getAttribute("clip-path")) {
          // Zaten kırpması varsa içine bir grup daha: iki kırpma da uygulanır
          const inner = doc.createElementNS(SVGNS, "g");
          inner.setAttribute("clip-path", `url(#${clip.id})`);
          while (user.firstChild) inner.appendChild(user.firstChild);
          user.appendChild(inner);
        } else user.setAttribute("clip-path", `url(#${clip.id})`);
      }
      mask.remove(); clips++;
    }
    return { clips, whites };
  }

  // Penpot dosyasındaki yazı içeriğinden (content) gerçek yazı tiplerini çıkarır.
  // SVG'deki font-family, yazının son ölçüm verisinden gelir ve çoğu zaman "sans-serif, sourcesanspro"
  // olarak kalmıştır; asıl tasarım yazı tipi içerik ağacındaki yapraklardadır.
  function textLeaves(node, out = []) {
    if (!node || typeof node !== "object") return out;
    if (typeof node.text === "string" && !Array.isArray(node.children)) {
      out.push({ text: node.text, family: node.fontFamily, weight: node.fontWeight, style: node.fontStyle, fontId: node.fontId });
    }
    for (const c of node.children || []) textLeaves(c, out);
    return out;
  }
  const fontName = (f) => (!f || f.toLowerCase() === "sourcesanspro" ? "Source Sans Pro" : f);
  const leafFor = (shape, runText) => {
    const leaves = (shape && shape.leaves || []).filter((l) => l.family);
    if (!leaves.length) return null;
    const run = (runText || "").trim();
    return leaves.find((l) => run && l.text.includes(run)) || leaves.find((l) => run && run.includes(l.text.trim()) && l.text.trim()) || leaves[0];
  };
  const GENERIC = ["sans-serif", "serif", "monospace", "cursive", "fantasy", "system-ui"];

  // Yazıları düzeltir: gerçek yazı tipi/kalınlık/stil yazılır, textLength kaldırılır ve
  // dominant-baseline="ideographic" yerine normal (alfabetik) taban çizgisine göre y yazılır.
  // Konum farkı, yazı tipi yüklenmiş olarak bu sayfada ölçülür.
  function fixTexts(doc, shapes) {
    const texts = Array.from(doc.getElementsByTagNameNS(SVGNS, "text"));
    if (!texts.length) return 0;
    const host = document.createElementNS(SVGNS, "svg");
    host.setAttribute("style", "position:absolute;left:-99999px;top:0;width:10px;height:10px;overflow:hidden");
    document.body.appendChild(host);
    const cache = {};
    let fixed = 0;
    try {
      for (const t of texts) {
        let style = t.getAttribute("style") || "";
        const owner = t.closest("[id^='shape-']");
        const sid = owner && (owner.getAttribute("id").match(/^shape-([0-9a-f-]{36})$/) || [])[1];
        const leaf = leafFor(sid && shapes[sid], t.textContent);
        const set = (prop, val) => {
          const re = new RegExp(`(^|;)\\s*${prop}\\s*:[^;]*`);
          style = re.test(style) ? style.replace(re, `$1 ${prop}: ${val}`) : `${style.replace(/;?\s*$/, ";")} ${prop}: ${val};`;
        };
        if (leaf) {
          set("font-family", `'${fontName(leaf.family)}', sans-serif`);
          if (leaf.weight) set("font-weight", leaf.weight);
          if (leaf.style) set("font-style", leaf.style);
        } else {
          style = style.replace(/font-family:\s*([^;]+)/, (m, list) => {
            const fams = list.split(",").map((f) => f.trim().replace(/^["']|["']$/g, "")).filter(Boolean).map(fontName);
            const sorted = [...fams.filter((f) => !GENERIC.includes(f.toLowerCase())), ...fams.filter((f) => GENERIC.includes(f.toLowerCase()))];
            return "font-family: " + sorted.map((f) => (GENERIC.includes(f.toLowerCase()) ? f : `'${f}'`)).join(", ");
          });
        }
        t.setAttribute("style", style);
        t.removeAttribute("textLength"); t.removeAttribute("lengthAdjust");
        const db = t.getAttribute("dominant-baseline");
        if (!db || db === "alphabetic" || db === "auto") continue;
        const key = db + "|" + (style.match(/font-[a-z]+:\s*[^;]+/g) || []).join("|");
        if (!(key in cache)) {
          const mk = (base) => {
            const e = document.createElementNS(SVGNS, "text");
            e.setAttribute("style", style); e.setAttribute("x", "0"); e.setAttribute("y", "1000");
            if (base) e.setAttribute("dominant-baseline", base);
            e.textContent = "Hxgİ"; host.appendChild(e);
            const y = e.getBBox().y; e.remove(); return y;
          };
          cache[key] = mk(db) - mk("alphabetic");
        }
        const dy = cache[key];
        for (const e of [t, ...t.querySelectorAll("tspan")]) {
          const y = e.getAttribute("y");
          if (y != null && y !== "") e.setAttribute("y", y.split(/[\s,]+/).map((v) => (parseFloat(v) + dy).toFixed(3)).join(" "));
        }
        t.removeAttribute("dominant-baseline");
        fixed++;
      }
    } finally { host.remove(); }
    return fixed;
  }

  // Tasarımda kullanılan Google yazı tiplerini sayfaya yükler (ölçüm ve görüntüye çevirme doğru olsun)
  async function loadFonts(families) {
    for (const f of families) {
      if (document.querySelector(`style[data-ppx-font="${f}"]`)) continue;
      try {
        const r = await fetch(`/internal/gfonts/css?family=${encodeURIComponent(f)}:100,200,300,400,500,600,700,800,900,100italic,400italic,700italic&display=block`);
        if (!r.ok) continue;
        const st = document.createElement("style"); st.dataset.ppxFont = f; st.textContent = await r.text();
        document.head.appendChild(st);
        await Promise.all([300, 400, 500, 600, 700, 800].map((w) => document.fonts.load(`${w} 20px '${f}'`).catch(() => null)));
      } catch (e) { /* yazı tipi yüklenemezse ölçüm yedek yazı tipiyle yapılır */ }
    }
  }

  // Penpot'un dış/iç kontur hilesini (maske ya da kırpma içinde iki kat kalın çizgi + <use>) düz bir
  // kontura çevirir; Figma ve Illustrator bu hileyi anlamıyor, konturu kaymış ya da hiç göstermiyordu.
  function fixStrokes(doc) {
    let n = 0;
    for (const g of Array.from(doc.querySelectorAll("g.outer-stroke-shape, g.inner-stroke-shape"))) {
      const def = g.querySelector("defs > [id^='stroke-shape-']");
      if (!def) continue;
      const outer = g.classList.contains("outer-stroke-shape");
      const src = outer ? g.querySelector(":scope > use[mask]") : def;
      const css = (el, prop) => ((el && el.getAttribute("style") || "").match(new RegExp(`(?:^|;)\\s*${prop}\\s*:\\s*([^;]+)`)) || [])[1];
      const stroke = css(src, "stroke"), width = parseFloat(css(src, "stroke-width") || "0");
      const out = def.cloneNode(true);
      out.removeAttribute("id");
      let st = (out.getAttribute("style") || "").replace(/(^|;)\s*(fill|fill-opacity|stroke|stroke-width|stroke-opacity)\s*:[^;]*/g, "").replace(/^;+/, "");
      if (stroke && stroke !== "none" && width > 0) {
        st += `; fill: none; stroke: ${stroke}; stroke-opacity: ${css(src, "stroke-opacity") || 1}; stroke-width: ${width / 2}`;
      } else st += "; fill: none; stroke: none";
      out.setAttribute("style", st.replace(/^;\s*/, ""));
      const tr = g.getAttribute("transform");
      if (tr && !IDENTITY.test(tr)) { const w = doc.createElementNS(SVGNS, "g"); w.setAttribute("transform", tr); w.appendChild(out); g.replaceWith(w); }
      else g.replaceWith(out);
      n++;
    }
    return n;
  }

  // Gölge, parlama ve bulanıklık (SVG filtreleri) Figma'da hiç, Illustrator'da düzgün çıkmıyor.
  //  - Gölge: yalnızca gölgenin kendisi görüntüye çevrilip öğenin arkasına konur; öğe düzenlenebilir kalır.
  //  - Bulanıklık ve diğerleri: öğe bütünüyle görüntüye çevrilir.
  // Ölçüm için belge gizli olarak sayfaya yerleştirilir; görüntüler 2x çözünürlükte çizilir.
  async function rasterizeEffects(doc, onProgress) {
    const targets = Array.from(doc.querySelectorAll("[filter]")).filter((e) =>
      !e.closest("defs,mask,clipPath,pattern,filter,symbol") && !e.parentElement.closest("[filter]"));
    if (!targets.length) return { shadows: 0, rasters: 0 };
    targets.forEach((e, i) => e.setAttribute("data-ppx-fx", i));
    const holder = document.createElement("div");
    holder.style.cssText = "position:absolute;left:-200000px;top:0;visibility:hidden;pointer-events:none";
    const live = document.importNode(doc.documentElement, true);
    holder.appendChild(live); document.body.appendChild(holder);
    const byId = (root, id) => root.querySelector(`[id="${id.replace(/["\\]/g, "\\$&")}"]`);
    const refsOf = (el) => {
      const ids = new Set();
      for (const e of [el, ...el.querySelectorAll("*")]) for (const a of e.attributes) {
        for (const m of a.value.matchAll(/url\(['"]?#([^)'"]+)['"]?\)/g)) ids.add(m[1]);
        if ((a.name === "href" || a.name === "xlink:href") && a.value.startsWith("#")) ids.add(a.value.slice(1));
      }
      return ids;
    };
    let shadows = 0, rasters = 0;
    try {
      for (let i = 0; i < targets.length; i++) {
        onProgress && onProgress(i + 1, targets.length);
        const t = targets[i], lt = live.querySelector(`[data-ppx-fx="${i}"]`);
        const filt = byId(doc, urlId(t.getAttribute("filter")) || "");
        if (!lt || !filt) continue;
        const prims = Array.from(filt.children);
        const last = prims[prims.length - 1];
        const shadowOnly = !!last && last.localName === "feBlend" && last.getAttribute("in") === "SourceGraphic";
        // Bölge: öğenin kutusu + filtre bölgesi (objectBoundingBox kesirleri)
        const bb = lt.getBBox();
        if (!bb.width || !bb.height) continue;
        let R = { x: bb.x, y: bb.y, w: bb.width, h: bb.height };
        if ((filt.getAttribute("filterUnits") || "objectBoundingBox") === "objectBoundingBox") {
          const fx = parseFloat(filt.getAttribute("x") ?? -0.1), fy = parseFloat(filt.getAttribute("y") ?? -0.1);
          const fw = parseFloat(filt.getAttribute("width") ?? 1.2), fh = parseFloat(filt.getAttribute("height") ?? 1.2);
          R = { x: bb.x + fx * bb.width, y: bb.y + fy * bb.height, w: fw * bb.width, h: fh * bb.height };
        } else if (filt.getAttribute("width")) {
          R = { x: +filt.getAttribute("x"), y: +filt.getAttribute("y"), w: +filt.getAttribute("width"), h: +filt.getAttribute("height") };
        }
        // Çizim belgesi: öğe + başvurduğu tanımlar (filtre, gradyan, kırpma…), öğenin kendi koordinatlarında
        const rd = document.implementation.createDocument(SVGNS, "svg", null);
        const root = rd.documentElement;
        root.setAttributeNS("http://www.w3.org/2000/xmlns/", "xmlns:xlink", XLINK);
        const scale = 2;
        root.setAttribute("viewBox", `${R.x} ${R.y} ${R.w} ${R.h}`);
        root.setAttribute("width", Math.ceil(R.w * scale)); root.setAttribute("height", Math.ceil(R.h * scale));
        const defs = rd.createElementNS(SVGNS, "defs"); root.appendChild(defs);
        const seen = new Set(), queue = [...refsOf(t)];
        while (queue.length) {
          const id = queue.shift(); if (seen.has(id)) continue; seen.add(id);
          const d = byId(doc, id); if (!d) continue;
          const c = rd.importNode(d, true);
          if (id === filt.id && shadowOnly) c.lastElementChild && c.removeChild(c.lastElementChild);   // yalnızca gölge
          defs.appendChild(c);
          for (const r of refsOf(d)) queue.push(r);
        }
        const tc = rd.importNode(t, true); tc.removeAttribute("transform"); root.appendChild(tc);
        const png = await new Promise((ok) => {
          const img = new Image();
          img.onload = () => {
            const c = document.createElement("canvas"); c.width = Math.ceil(R.w * scale); c.height = Math.ceil(R.h * scale);
            c.getContext("2d").drawImage(img, 0, 0, c.width, c.height);
            ok(c.toDataURL("image/png")); URL.revokeObjectURL(img.src);
          };
          img.onerror = () => ok(null);
          img.src = URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(rd)], { type: "image/svg+xml" }));
        });
        if (!png) continue;
        const im = doc.createElementNS(SVGNS, "image");
        im.setAttribute("x", R.x); im.setAttribute("y", R.y); im.setAttribute("width", R.w); im.setAttribute("height", R.h);
        im.setAttribute("href", png); im.setAttribute("preserveAspectRatio", "none");
        const tr = t.getAttribute("transform");
        const placed = tr && !IDENTITY.test(tr) ? (() => { const g = doc.createElementNS(SVGNS, "g"); g.setAttribute("transform", tr); g.appendChild(im); return g; })() : im;
        if (shadowOnly) {
          im.setAttribute("id", "Gölge");
          t.parentNode.insertBefore(placed, t);
          t.removeAttribute("filter");
          shadows++;
        } else {
          t.replaceWith(placed);
          rasters++;
        }
      }
    } finally {
      holder.remove();
      for (const e of doc.querySelectorAll("[data-ppx-fx]")) e.removeAttribute("data-ppx-fx");
    }
    return { shadows, rasters };
  }

  function simplifyLayers(doc, names) {
    const referenced = new Set();
    for (const e of doc.getElementsByTagName("*")) {
      for (const a of e.attributes) for (const m of a.value.matchAll(/#([^)\s"']+)/g)) referenced.add(m[1]);
    }
    const harmless = (g) => {
      for (const a of Array.from(g.attributes)) {
        const n = a.name, v = a.value.trim();
        if (n === "id") { if (referenced.has(v)) return false; continue; }
        if (n === "class" || ["x", "y", "width", "height", "rx", "ry"].includes(n)) continue;
        if (n === "opacity" && parseFloat(v) === 1) continue;
        if (n === "style" && /^(opacity:\s*1;?\s*)?$/.test(v)) continue;
        if (n === "transform" && IDENTITY.test(v)) continue;
        return false;
      }
      return true;
    };
    const shapeId = (g) => ((g.getAttribute("id") || "").match(/^shape-([0-9a-f-]{36})$/) || [])[1];
    let changed = true, guard = 0;
    while (changed && guard++ < 50) {
      changed = false;
      for (const g of Array.from(doc.getElementsByTagNameNS(SVGNS, "g")).reverse()) {
        if (!g.parentNode || g === doc.documentElement || g.closest("clipPath,mask,pattern,defs")) continue;
        const kids = Array.from(g.children).filter((k) => k.localName !== "defs" || k.children.length);
        if (shapeId(g)) {
          if (kids.length === 1 && harmless(g) && kids[0].localName !== "defs") {
            const k = kids[0];
            if (!k.getAttribute("id") || !referenced.has(k.getAttribute("id"))) k.setAttribute("id", g.getAttribute("id"));
            for (const d of Array.from(g.children)) if (d !== k) g.parentNode.insertBefore(d, g);
            g.replaceWith(k); changed = true;
          }
          continue;
        }
        if (harmless(g)) {
          while (g.firstChild) g.parentNode.insertBefore(g.firstChild, g);
          g.remove(); changed = true;
        }
      }
    }
    const used = {};
    for (const e of Array.from(doc.querySelectorAll("[id^='shape-']"))) {
      const sid = (e.getAttribute("id").match(/^shape-([0-9a-f-]{36})$/) || [])[1];
      if (!sid || referenced.has(e.getAttribute("id"))) continue;
      const nm = (names[sid] || "").trim();
      if (!nm) { e.removeAttribute("id"); continue; }
      used[nm] = (used[nm] || 0) + 1;
      e.setAttribute("id", used[nm] > 1 ? `${nm} ${used[nm]}` : nm);
    }
  }

  function addXlinkHrefs(doc) {
    const root = doc.documentElement;
    if (!root.getAttribute("xmlns:xlink")) root.setAttributeNS("http://www.w3.org/2000/xmlns/", "xmlns:xlink", XLINK);
    for (const img of doc.getElementsByTagNameNS(SVGNS, "image")) {
      const h = img.getAttribute("href");
      // Yalnızca xlink:href (SVG 1.1): Illustrator, Figma ve tarayıcılar okur; ikisini birden yazmak
      // görselleri dosyada iki kez taşır
      if (h) { if (!img.getAttributeNS(XLINK, "href")) img.setAttributeNS(XLINK, "xlink:href", h); img.removeAttribute("href"); }
    }
  }

  async function prepareSvg(svgText, shapes = {}, onProgress) {
    const doc = new DOMParser().parseFromString(svgText, "image/svg+xml");
    if (doc.querySelector("parsererror")) return { svg: svgText, report: { error: "SVG okunamadı" } };
    const names = {};
    for (const [id, sh] of Object.entries(shapes)) if (sh.name) names[id] = sh.name;
    flattenImagePatterns(doc);
    const masks = fixMasks(doc);
    const strokes = fixStrokes(doc);
    const texts = fixTexts(doc, shapes);
    const effects = await rasterizeEffects(doc, onProgress);
    simplifyLayers(doc, names);
    addXlinkHrefs(doc);
    return { svg: new XMLSerializer().serializeToString(doc), report: { masks, strokes, texts, effects } };
  }
  window.__ppxTest = { prepareSvg, loadFonts, textLeaves };   // (yalnızca test için dışa açık)

  // Birden fazla board'un SVG'sini, Penpot'taki konumlarını koruyarak tek SVG'de birleştirir
  const mergeSvgs = (parts) => {
    if (parts.length === 1) return parts[0].svg;
    const minX = Math.min(...parts.map((p) => p.board.x)), minY = Math.min(...parts.map((p) => p.board.y));
    const maxX = Math.max(...parts.map((p) => p.board.x + p.board.width)), maxY = Math.max(...parts.map((p) => p.board.y + p.board.height));
    const W = Math.ceil(maxX - minX), H = Math.ceil(maxY - minY);
    const ns = "http://www.w3.org/2000/svg";
    const out = document.implementation.createDocument(ns, "svg", null);
    const root = out.documentElement;
    root.setAttribute("width", W); root.setAttribute("height", H); root.setAttribute("viewBox", `0 0 ${W} ${H}`);
    root.setAttribute("xmlns:xlink", "http://www.w3.org/1999/xlink");
    for (const p of parts) {
      const doc = new DOMParser().parseFromString(p.svg, "image/svg+xml");
      const s = doc.documentElement;
      const g = out.createElementNS(ns, "svg");
      g.setAttribute("x", p.board.x - minX); g.setAttribute("y", p.board.y - minY);
      g.setAttribute("width", p.board.width); g.setAttribute("height", p.board.height);
      g.setAttribute("viewBox", s.getAttribute("viewBox") || `0 0 ${p.board.width} ${p.board.height}`);
      g.setAttribute("id", "board-" + p.board.id);
      for (const c of Array.from(s.childNodes)) g.appendChild(out.importNode(c, true));
      root.appendChild(g);
    }
    return new XMLSerializer().serializeToString(out);
  };

  // ------------------------------------------------------------------ görünüm
  const CSS = `
  .ppx-section{padding:0 0 4px 0;margin:0 0 8px 0}
  .ppx-title{font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:var(--color-foreground-secondary);font-weight:500;padding:12px 8px 8px 8px}
  .ppx-cards{display:flex;flex-direction:column;gap:6px;padding:0 4px}
  .ppx-card{display:flex;align-items:center;gap:10px;padding:8px 10px;border-radius:8px;cursor:pointer;
    background:var(--color-background-tertiary);border:1px solid transparent;color:var(--color-foreground-primary);
    font:inherit;font-size:14px;text-align:left;transition:background .15s,border-color .15s}
  .ppx-card:hover{border-color:var(--color-accent-primary);background:var(--color-background-quaternary)}
  .ppx-card small{display:block;font-size:11px;color:var(--color-foreground-secondary);margin-top:1px}
  .ppx-logo{width:28px;height:28px;flex:none;border-radius:7px;display:grid;place-items:center}
  .ppx-overlay{position:fixed;inset:0;z-index:100000;background:rgba(0,0,0,.55);display:grid;place-items:center;
    animation:ppx-fade .15s ease-out}
  @keyframes ppx-fade{from{opacity:0}to{opacity:1}}
  .ppx-modal{width:min(560px,92vw);max-height:min(640px,86vh);display:flex;flex-direction:column;border-radius:12px;
    background:var(--color-background-primary);color:var(--color-foreground-primary);
    border:1px solid var(--color-background-quaternary);box-shadow:0 20px 60px rgba(0,0,0,.45);overflow:hidden}
  .ppx-head{display:flex;align-items:center;gap:12px;padding:18px 20px 14px}
  .ppx-head h2{font-size:18px;font-weight:500;margin:0}
  .ppx-head p{margin:2px 0 0;font-size:12px;color:var(--color-foreground-secondary)}
  .ppx-x{margin-left:auto;background:none;border:0;color:var(--color-foreground-secondary);font-size:20px;cursor:pointer;
    width:32px;height:32px;border-radius:6px}
  .ppx-x:hover{background:var(--color-background-tertiary);color:var(--color-foreground-primary)}
  .ppx-search{margin:0 20px 10px;padding:9px 12px;border-radius:8px;border:1px solid var(--color-background-quaternary);
    background:var(--color-background-tertiary);color:var(--color-foreground-primary);font:inherit;font-size:14px;outline:none}
  .ppx-search:focus{border-color:var(--color-accent-primary)}
  .ppx-list{overflow:auto;padding:0 12px 12px;flex:1}
  .ppx-group{font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:var(--color-foreground-secondary);padding:12px 8px 6px}
  .ppx-row{display:flex;align-items:center;gap:12px;width:100%;padding:10px;border-radius:8px;border:0;background:none;
    color:inherit;font:inherit;font-size:14px;text-align:left;cursor:pointer}
  .ppx-row:hover{background:var(--color-background-tertiary)}
  .ppx-row .ppx-meta{margin-left:auto;font-size:12px;color:var(--color-foreground-secondary);white-space:nowrap}
  .ppx-ficon{width:34px;height:34px;flex:none;border-radius:6px;background:var(--color-background-tertiary);display:grid;place-items:center;
    color:var(--color-foreground-secondary)}
  .ppx-check{display:flex;align-items:center;gap:12px;padding:9px 10px;border-radius:8px;cursor:pointer;font-size:14px}
  .ppx-check:hover{background:var(--color-background-tertiary)}
  .ppx-check input{accent-color:var(--color-accent-primary);width:16px;height:16px}
  .ppx-check .ppx-meta{margin-left:auto;font-size:12px;color:var(--color-foreground-secondary)}
  .ppx-foot{display:flex;align-items:center;gap:10px;padding:14px 20px;border-top:1px solid var(--color-background-quaternary)}
  .ppx-foot .ppx-status{font-size:12px;color:var(--color-foreground-secondary);flex:1}
  .ppx-btn{padding:9px 16px;border-radius:8px;border:1px solid var(--color-background-quaternary);background:var(--color-background-tertiary);
    color:var(--color-foreground-primary);font:inherit;font-size:14px;cursor:pointer}
  .ppx-btn.primary{background:var(--color-accent-primary);border-color:var(--color-accent-primary);color:var(--color-background-secondary);font-weight:500}
  .ppx-btn:disabled{opacity:.5;cursor:default}
  .ppx-empty{padding:40px 20px;text-align:center;color:var(--color-foreground-secondary);font-size:14px}
  .ppx-spin{width:16px;height:16px;border:2px solid var(--color-background-quaternary);border-top-color:var(--color-accent-primary);
    border-radius:50%;animation:ppx-r .8s linear infinite;display:inline-block;vertical-align:-3px;margin-right:8px}
  @keyframes ppx-r{to{transform:rotate(360deg)}}
  .ppx-fmt{display:flex;gap:4px;margin:0 20px 10px;padding:3px;border-radius:8px;background:var(--color-background-tertiary);width:max-content}
  .ppx-seg{padding:6px 14px;border:0;border-radius:6px;background:none;color:var(--color-foreground-secondary);font:inherit;font-size:13px;cursor:pointer}
  .ppx-seg.on{background:var(--color-background-quaternary);color:var(--color-foreground-primary)}
  .ppx-note{margin:0 20px 12px;padding:10px 12px;border-radius:8px;font-size:13px;background:var(--color-background-tertiary);color:var(--color-foreground-secondary)}
  .ppx-note b{color:var(--color-foreground-primary)}
  `;
  const LOGOS = {
    figma: `<svg width="16" height="24" viewBox="0 0 38 57"><path fill="#1abcfe" d="M19 28.5a9.5 9.5 0 1 1 19 0 9.5 9.5 0 0 1-19 0z"/><path fill="#0acf83" d="M0 47.5A9.5 9.5 0 0 1 9.5 38H19v9.5a9.5 9.5 0 1 1-19 0z"/><path fill="#ff7262" d="M19 0v19h9.5a9.5 9.5 0 1 0 0-19H19z"/><path fill="#f24e1e" d="M0 9.5A9.5 9.5 0 0 0 9.5 19H19V0H9.5A9.5 9.5 0 0 0 0 9.5z"/><path fill="#a259ff" d="M0 28.5A9.5 9.5 0 0 0 9.5 38H19V19H9.5A9.5 9.5 0 0 0 0 28.5z"/></svg>`,
    illustrator: `<svg width="28" height="28" viewBox="0 0 28 28"><rect width="28" height="28" rx="7" fill="#330000"/><text x="14" y="19" text-anchor="middle" font-family="-apple-system,Helvetica,Arial" font-weight="700" font-size="13" fill="#ff9a00">Ai</text></svg>`,
  };
  const TARGET = {
    figma: { title: "Figma'da aç", sub: "Panoya kopyalanır, Figma açılır", type: "svg", bg: "#1e1e1e" },
    illustrator: { title: "Illustrator'da aç", sub: "Görseller gömülü SVG ya da PDF", type: "svg", bg: "transparent" },
  };
  const FILE_ICON = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/></svg>`;

  // ------------------------------------------------------------------ sol menü kartları
  function injectSidebar() {
    const anchor = document.querySelector('[data-testid="pinned-projects"]');
    if (!anchor || document.getElementById("ppx-aktar")) return;
    if (!document.getElementById("ppx-style")) document.head.append(el("style", { id: "ppx-style" }, CSS));
    const card = (key) => el("button", { class: "ppx-card", type: "button", onclick: () => openPicker(key) },
      el("span", { class: "ppx-logo", style: `background:${TARGET[key].bg}`, html: LOGOS[key] }),
      el("span", {}, TARGET[key].title, el("small", {}, TARGET[key].sub)));
    anchor.parentNode.insertBefore(
      el("div", { id: "ppx-aktar", class: "ppx-section" },
        el("div", { class: "ppx-title" }, "Başka uygulamada aç"),
        el("div", { class: "ppx-cards" }, card("figma"), card("illustrator"))),
      anchor);
  }
  new MutationObserver(injectSidebar).observe(document.documentElement, { childList: true, subtree: true });
  injectSidebar();

  // ------------------------------------------------------------------ seçim penceresi
  function openPicker(target) {
    const T = TARGET[target];
    let closed = false;
    const close = () => { closed = true; overlay.remove(); document.removeEventListener("keydown", onKey, true); };
    const onKey = (e) => { if (e.key === "Escape") { e.stopPropagation(); close(); } };
    document.addEventListener("keydown", onKey, true);

    const sub = el("p", {}, "Hangi dosyanızı açmak istersiniz?");
    const head = el("div", { class: "ppx-head" },
      el("span", { class: "ppx-logo", style: `width:36px;height:36px;background:${T.bg}`, html: LOGOS[target] }),
      el("div", {}, el("h2", {}, T.title), sub),
      el("button", { class: "ppx-x", type: "button", title: "Kapat", onclick: close }, "×"));
    const body = el("div", { style: "display:flex;flex-direction:column;min-height:0;flex:1" });
    const modal = el("div", { class: "ppx-modal", role: "dialog" }, head, body);
    const overlay = el("div", { class: "ppx-overlay", onclick: (e) => { if (e.target === overlay) close(); } }, modal);
    document.body.append(overlay);

    const loading = (text) => { body.replaceChildren(el("div", { class: "ppx-empty" }, el("span", { class: "ppx-spin" }), text)); };
    const fail = (text) => { body.replaceChildren(el("div", { class: "ppx-empty" }, text)); };

    // 1) Dosya listesi
    (async () => {
      loading("Dosyalar yükleniyor…");
      try {
        let teamId = currentTeamId();
        if (!teamId) { const teams = await rpc("get-teams"); teamId = (teams.find((t) => t.isDefault) || teams[0]).id; }
        const projects = await rpc("get-projects", { teamId });
        const groups = [];
        for (const p of projects.filter((p) => !p.deletedAt)) {
          const files = (await rpc("get-project-files", { projectId: p.id })).filter((f) => !f.deletedAt);
          if (files.length) groups.push({ name: p.isDefault ? "Taslaklar" : p.name, files });
        }
        if (closed) return;
        if (!groups.length) return fail("Bu takımda henüz dosya yok.");
        const search = el("input", { class: "ppx-search", placeholder: "Dosya ara…", type: "search" });
        const list = el("div", { class: "ppx-list" });
        const render = () => {
          const q = search.value.trim().toLocaleLowerCase("tr");
          list.replaceChildren();
          for (const g of groups) {
            const fs = g.files.filter((f) => !q || f.name.toLocaleLowerCase("tr").includes(q))
              .sort((a, b) => String(b.modifiedAt).localeCompare(String(a.modifiedAt)));
            if (!fs.length) continue;
            list.append(el("div", { class: "ppx-group" }, g.name));
            for (const f of fs) list.append(el("button", { class: "ppx-row", type: "button", onclick: () => pickBoards(f) },
              el("span", { class: "ppx-ficon", html: FILE_ICON }), f.name, el("span", { class: "ppx-meta" }, fmtDate(f.modifiedAt))));
          }
          if (!list.children.length) list.append(el("div", { class: "ppx-empty" }, "Eşleşen dosya yok."));
        };
        search.addEventListener("input", render);
        render();
        body.replaceChildren(search, list);
        search.focus();
      } catch (e) { fail("Dosyalar yüklenemedi: " + e.message); }
    })();

    // 2) Board seçimi ve aktarma
    async function pickBoards(file) {
      sub.textContent = file.name;
      loading("Dosya açılıyor…");
      let boards; const shapes = {};
      try {
        const full = await rpc("get-file", { id: file.id });
        const data = full.data || {};
        const pages = (data.pages || []).map((pid) => ({ id: pid, page: (data.pagesIndex || {})[pid] })).filter((x) => x.page);
        boards = [];
        for (const { id: pageId, page } of pages) {
          for (const o of Object.values(page.objects || {})) {
            if (o.id) shapes[o.id] = { name: o.name, type: o.type, leaves: o.type === "text" ? textLeaves(o.content) : null };
            if (o.type === "frame" && o.id !== ROOT_ID && o.parentId === ROOT_ID)
              boards.push({ id: o.id, name: o.name || "Board", pageId, pageName: page.name, x: o.x, y: o.y, width: o.width, height: o.height });
          }
        }
      } catch (e) { return fail("Dosya okunamadı: " + e.message); }
      if (closed) return;
      if (!boards.length) return fail("Bu dosyada çalışma alanı (board) yok. Penpot'ta en az bir board oluşturun.");

      const checks = [];
      const list = el("div", { class: "ppx-list" });
      const byPage = {};
      for (const b of boards) (byPage[b.pageName] = byPage[b.pageName] || []).push(b);
      for (const [pageName, bs] of Object.entries(byPage)) {
        list.append(el("div", { class: "ppx-group" }, pageName));
        for (const b of bs) {
          const cb = el("input", { type: "checkbox" }); cb.checked = true; cb.onchange = update;
          checks.push({ cb, b });
          list.append(el("label", { class: "ppx-check" }, cb, b.name, el("span", { class: "ppx-meta" }, `${Math.round(b.width)} × ${Math.round(b.height)}`)));
        }
      }
      const all = el("button", { class: "ppx-btn", type: "button", onclick: () => { const v = !checks.every((c) => c.cb.checked); checks.forEach((c) => (c.cb.checked = v)); update(); } }, "Tümü");
      const back = el("button", { class: "ppx-btn", type: "button", onclick: () => { close(); openPicker(target); } }, "Geri");
      const status = el("span", { class: "ppx-status" });
      const go = el("button", { class: "ppx-btn primary", type: "button", onclick: run }, T.title);
      function update() { const n = checks.filter((c) => c.cb.checked).length; status.textContent = n + " çalışma alanı seçili"; go.disabled = n === 0; }
      update();
      // Illustrator için biçim: SVG (görseller gömülü, önerilen) ya da PDF
      let fmt = "svg";
      const fmtBox = target === "illustrator" ? el("div", { class: "ppx-fmt" },
        ...[["svg", "SVG (önerilen)"], ["pdf", "PDF"]].map(([v, label]) => {
          const b = el("button", { type: "button", class: "ppx-seg" + (v === fmt ? " on" : ""), onclick: () => {
            fmt = v; fmtBox.querySelectorAll(".ppx-seg").forEach((x) => x.classList.toggle("on", x === b)); setNote(); } }, label);
          return b;
        })) : null;
      const note = el("div", { class: "ppx-note" });
      const setNote = () => {
        note.innerHTML = target === "figma"
          ? "Seçilenler <b>panoya kopyalanır</b> (görseller dahil) ve Figma açılır. Figma'da bir dosyaya girip <b>⌘V</b> ile yapıştırın."
          : fmt === "svg"
            ? "Seçilenler görselleri gömülü tek bir <b>SVG</b> olarak İndirilenler › Penpot Aktarım klasörüne kaydedilir ve Illustrator'da açılır."
            : "Seçilenler tek bir <b>PDF</b> olarak kaydedilir ve Illustrator'da açılır. Görsellerde sorun olursa SVG'yi deneyin.";
      };
      setNote();
      body.replaceChildren(...[fmtBox, note, list, el("div", { class: "ppx-foot" }, status, back, all, go)].filter(Boolean));

      async function run() {
        const chosen = checks.filter((c) => c.cb.checked).map((c) => c.b);
        go.disabled = all.disabled = back.disabled = true;
        try {
          const profile = await rpc("get-profile");
          // Tasarımdaki yazı tipleri: sayfaya yükle (doğru ölçüm) ve Mac'te yoksa kur (Figma/Illustrator için)
          const fams = [...new Set(Object.values(shapes).flatMap((sh) => (sh.leaves || []).map((l) => fontName(l.family))).filter(Boolean))];
          if (fams.length) {
            status.replaceChildren(el("span", { class: "ppx-spin" }), "Yazı tipleri hazırlanıyor…");
            await loadFonts(fams);
            try {
              const fr = await native({ kind: "fonts", families: fams });
              if (fr && fr.installed && fr.installed.length) log("Kurulan yazı tipleri: " + fr.installed.join(", "));
              if (fr && fr.missing && fr.missing.length) log("Bulunamayan yazı tipleri: " + fr.missing.join(", "));
            } catch (e) { log("Yazı tipi kurulumu: " + e.message); }
          }
          const parts = [];
          for (let i = 0; i < chosen.length; i++) {
            if (closed) return;
            status.replaceChildren(el("span", { class: "ppx-spin" }), `Dışa aktarılıyor ${i + 1}/${chosen.length}: ${chosen[i].name}`);
            const type = target === "figma" ? "svg" : fmt;
            let data = await exportOne(profile.id, file.id, chosen[i].pageId, chosen[i], type);
            if (type === "svg") data = await inlineAssets(data, (k, n) =>
              status.replaceChildren(el("span", { class: "ppx-spin" }), `Görseller ekleniyor ${k}/${n}: ${chosen[i].name}`));
            if (type === "svg") {
              const r = await prepareSvg(data, shapes, (k, n) =>
                status.replaceChildren(el("span", { class: "ppx-spin" }), `Efektler hazırlanıyor ${k}/${n}: ${chosen[i].name}`));
              data = r.svg;
              log("Hazırlandı: " + chosen[i].name + " " + JSON.stringify(r.report));
            }
            parts.push({ board: chosen[i], data });
          }
          const asSvg = target === "figma" || fmt === "svg";
          status.replaceChildren(el("span", { class: "ppx-spin" }), target === "figma" ? "Figma açılıyor…" : "Illustrator açılıyor…");
          const svg = asSvg ? mergeSvgs(parts.map((p) => ({ board: p.board, svg: p.data }))) : null;
          const msg = target === "figma" ? { kind: "figma", name: file.name, svg }
            : asSvg ? { kind: "illustrator", name: file.name, svg }
            : { kind: "illustrator", name: file.name, pdfs: parts.map((p) => p.data) };
          const result = await native(msg);
          if (result && result.error) throw new Error(result.error);
          body.replaceChildren(el("div", { class: "ppx-empty" },
            el("div", { style: "font-size:32px;margin-bottom:8px" }, "✓"),
            target === "figma"
              ? el("div", { html: "Tasarım panoya kopyalandı ve Figma açıldı.<br>Figma'da bir dosyaya girip <b>⌘V</b> ile yapıştırın.<br><br><span style='font-size:12px'>Yedek SVG: İndirilenler klasörü</span>" })
              : el("div", { html: (asSvg ? "SVG" : "PDF") + " İndirilenler › Penpot Aktarım klasörüne kaydedildi ve Illustrator'da açılıyor." }),
            el("div", { style: "margin-top:18px" }, el("button", { class: "ppx-btn", type: "button", onclick: close }, "Kapat"))));
        } catch (e) {
          status.textContent = "Hata: " + e.message;
          go.disabled = all.disabled = back.disabled = false;
        }
      }
    }
  }
})();
