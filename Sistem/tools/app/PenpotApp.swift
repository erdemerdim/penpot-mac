// Penpot masaüstü uygulaması: macOS'un kendi web motoruyla (WKWebView) yerel Penpot'u açar.
// Kendi penceresi, Dock ikonu ve menüsü vardır; Penpot servislerini başlatır, kapanınca durdurur.
// Derleme: tools/app/build.sh
import AppKit
import WebKit

let penpotURL = URL(string: "http://localhost:9001/")!
let readyURL = URL(string: "http://127.0.0.1:6060/readyz")!
// Penpot index.html sayfasının ilk başlığı; arayüz çizilince değişir
let initialPageTitle = "Penpot | Full-stack design"

// İki çalışma şekli:
//  - Kurulum klasörü (kurulum.sh): uygulamanın yanındaki "Sistem" klasörü kullanılır.
//  - Tek parça uygulama (DMG): bileşenler paketin içindedir (Contents/Resources/runtime);
//    veriler ~/Library/Application Support/Penpot/Sistem altında tutulur (runtime/hazirla.sh kurar).
let appFolder = Bundle.main.bundleURL.deletingLastPathComponent()
let bundledRuntime = Bundle.main.resourceURL!.appendingPathComponent("runtime")
let isStandalone = FileManager.default.fileExists(atPath: bundledRuntime.appendingPathComponent("start.sh").path)
let systemFolder = isStandalone
    ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Penpot/Sistem")
    : appFolder.appendingPathComponent("Sistem")
let logURL = systemFolder.appendingPathComponent("logs/app.log")

func log(_ msg: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(msg)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.data(using: .utf8)!.write(to: logURL)
    }
}

func runScript(_ name: String, wait: Bool, in folder: URL = systemFolder) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [folder.appendingPathComponent(name).path]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { log("\(name) çalıştırılamadı: \(error)"); return -1 }
    if wait { p.waitUntilExit(); return p.terminationStatus }
    return 0
}

// WebKit'in genel olmayan (SPI) bir BOOL ayarını, varsa güvenle uygular.
// Ayar bu macOS sürümünde yoksa hiçbir şey yapmaz ve false döner.
func setPrivateBool(_ obj: NSObject, _ selName: String, _ value: Bool) -> Bool {
    let sel = NSSelectorFromString(selName)
    guard obj.responds(to: sel), let m = class_getInstanceMethod(type(of: obj), sel) else { return false }
    typealias F = @convention(c) (AnyObject, Selector, Bool) -> Void
    unsafeBitCast(method_getImplementation(m), to: F.self)(obj, sel, value)
    return true
}

// stop.sh çalışırken var olan kilit dosyası; içindeki PID yaşıyorsa durdurma sürüyordur
let stopLockURL = systemFolder.appendingPathComponent("data/stopping.lock")
func stopInProgress() -> Bool {
    guard let s = try? String(contentsOf: stopLockURL, encoding: .utf8),
          let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
    if kill(pid, 0) == 0 { return true }
    try? FileManager.default.removeItem(at: stopLockURL)   // yarım kalmış eski kilit
    return false
}

func backendReady() -> Bool {
    var req = URLRequest(url: readyURL); req.timeoutInterval = 2
    let sem = DispatchSemaphore(value: 0); var ok = false
    URLSession.shared.dataTask(with: req) { _, resp, _ in
        ok = (resp as? HTTPURLResponse)?.statusCode == 200; sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + 3)
    return ok
}

// Arayüzü sunan yerel proxy (port 9001) cevap veriyor mu?
func frontendReady() -> Bool {
    var req = URLRequest(url: penpotURL); req.timeoutInterval = 1; req.httpMethod = "HEAD"
    let sem = DispatchSemaphore(value: 0); var ok = false
    URLSession.shared.dataTask(with: req) { _, resp, _ in
        ok = (resp as? HTTPURLResponse) != nil; sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + 2)
    return ok
}

// Sayfadaki hataları ve temel yetenekleri log'a yazan betik
let diagnosticsJS = """
(function(){
  const post = (kind, msg) => { try { window.webkit.messageHandlers.penpotApp.postMessage({kind, msg: String(msg).slice(0, 500)}); } catch(e) {} };
  window.addEventListener('error', e => post('js-error', (e.message || e) + ' @ ' + (e.filename || '') + ':' + (e.lineno || '')));
  window.addEventListener('unhandledrejection', e => post('js-rejection', e.reason && (e.reason.message || e.reason)));
  const origErr = console.error; console.error = function(...a){ post('console-error', a.map(x => x && x.message ? x.message : x).join(' ')); return origErr.apply(console, a); };
  window.addEventListener('load', () => {
    const c = document.createElement('canvas');
    post('capabilities', JSON.stringify({ webgl2: !!c.getContext('webgl2'), wasm: typeof WebAssembly === 'object', ua: navigator.userAgent }));
    // Açılış süresi ölçümü: en uzun süren kaynaklar
    setTimeout(() => {
      const n = performance.getEntriesByType('navigation')[0] || {};
      const r = performance.getEntriesByType('resource').sort((a, b) => b.duration - a.duration).slice(0, 5)
        .map(x => x.name.split('/').pop().split('?')[0] + '=' + Math.round(x.duration) + 'ms');
      post('timing', 'dcl=' + Math.round(n.domContentLoadedEventEnd || 0) + 'ms load=' + Math.round(n.loadEventEnd || 0) + 'ms en-uzun: ' + r.join(', '));
    }, 0);
  });
  window.addEventListener('hashchange', () => post('route', Math.round(performance.now()) + 'ms ' + location.hash.split('?')[0]));
})();
"""

// Penpot boşluk vb. tuşları kullanır ama tarayıcıya "işlendi" demez; tuş macOS'a kadar ulaşır ve
// "bu tuşu karşılayan yok" uyarı sesi (bip) çalar. Kısayollar menüden işlendiği için bu sesi kapatıyoruz.
final class PenpotWindow: NSWindow {
    override func noResponder(for eventSelector: Selector) {
        if eventSelector == #selector(NSResponder.keyDown(with:)) || eventSelector == #selector(NSResponder.keyUp(with:)) { return }
        super.noResponder(for: eventSelector)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler, NSWindowDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var loadingLabel: NSTextField!
    var spinner: NSProgressIndicator!
    var stopping = false
    var relaunchAfterStop = false
    var noNapActivity: NSObjectProtocol?
    var titleObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ note: Notification) {
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        log("Uygulama açıldı")
        buildMenu()
        buildWindow()
        startServicesThenLoad()
    }

    // MARK: Pencere ve web görünümü
    func buildWindow() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()                 // oturum ve çerezler kalıcı
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled") // sağ tık > Öğeyi İncele
        cfg.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15" // Penpot Safari olarak tanısın

        // Pencere arka plandayken Penpot'un (ve MCP eklentisinin) yavaşlamaması için:
        // 1) macOS App Nap'i kapat  2) gizli sayfa zamanlayıcı kısıtlamasını kapat
        // 3) görünürlüğe bağlı süreç bastırmayı kapat (4. ayar web görünümü oluşturulunca uygulanır)
        noNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Penpot arka planda da tam hızda çalışmalı (MCP bağlantısı)")
        let p = cfg.preferences
        let r1 = setPrivateBool(p, "_setHiddenPageDOMTimerThrottlingEnabled:", false)
        let r2 = setPrivateBool(p, "_setHiddenPageDOMTimerThrottlingAutoIncreases:", false)
        let r3 = setPrivateBool(p, "_setPageVisibilityBasedProcessSuppressionEnabled:", false)
        let ucc = WKUserContentController()
        ucc.add(self, name: "penpotApp")
        ucc.addUserScript(WKUserScript(source: diagnosticsJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController = ucc

        webView = WKWebView(frame: .zero, configuration: cfg)
        let r4 = setPrivateBool(webView, "_setWindowOcclusionDetectionEnabled:", false)
        log("Arka plan yavaşlatma kapatıldı: zamanlayıcı=\(r1) otomatik-artış=\(r2) süreç-bastırma=\(r3) pencere-örtülme=\(r4) appnap=kapalı")
        webView.navigationDelegate = self
        // Başlık çubuğunda açık dosyanın adı: Penpot sayfa başlığı "X1122 - Penpot" gibidir
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            guard let self = self else { return }
            let t = (wv.title ?? "").trimmingCharacters(in: .whitespaces)
            log("Sayfa başlığı: \(t)")   // açılış süresi ölçümü: pano/dosya ne zaman hazır oldu
            DispatchQueue.main.async {
                self.window?.title = t.isEmpty ? "Penpot" : t
                // Penpot kendi arayüzünü çizince başlığı değiştirir ("Projeler - …", dosya adı, giriş sayfası…):
                // web görünümünü ancak o zaman göster. Böylece açılışta yükleme ekranından sonra
                // Penpot'un beyaz ön-yükleme sayfası bir an görünüp kaybolmaz.
                if !t.isEmpty && t != initialPageTitle { self.revealWebView() }
            }
        }
        // Web görünümü sayfa çizilmeden önce beyaz zemin göstermesin; pencerenin koyu zemini görünsün
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) { webView.underPageBackgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1) }
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        webView.isHidden = true
        if #available(macOS 13.3, *) { webView.isInspectable = true }

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor
        webView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(webView)

        spinner = NSProgressIndicator()
        spinner.style = .spinning; spinner.controlSize = .regular
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)
        content.addSubview(spinner)

        loadingLabel = NSTextField(labelWithString: "Penpot başlatılıyor…")
        loadingLabel.textColor = .secondaryLabelColor
        loadingLabel.font = .systemFont(ofSize: 15)
        loadingLabel.alignment = .center
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(loadingLabel)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -16),
            loadingLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 14),
            loadingLabel.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -40),
        ])

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NSRect(x: 0, y: 0, width: min(1600, screen.width * 0.9), height: min(1000, screen.height * 0.9))
        // Standart başlık çubuğu: pencere buradan tutulup taşınır, çift tıklayınca büyür/küçülür.
        // (İçerik başlık çubuğunun altında başlar; Penpot'un üst menüleri sürüklemeyi engellemez.)
        window = PenpotWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Penpot"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.appearance = NSAppearance(named: .darkAqua)   // Penpot'un koyu temasıyla uyumlu koyu başlık çubuğu
        window.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        window.minSize = NSSize(width: 900, height: 600)
        window.contentView = content
        // Kapatınca pencere nesnesi bellekten silinmesin: kapanış ekranı aynı pencerede gösterilir
        // (varsayılan "true" iken kapanış kodu silinmiş pencereye erişip uygulamayı çökertiyordu)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("PenpotMainWindow")   // boyut ve konum hatırlanır
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showStatus(_ text: String, spinning: Bool = true) {
        loadingLabel.stringValue = text
        loadingLabel.isHidden = false
        spinner.isHidden = !spinning
        if spinning { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    // MARK: Tek parça uygulama: ilk hazırlık
    // Paket DMG'den kopyalanmadan açıldıysa (salt okunur disk görüntüsü ya da macOS'un geçici
    // "App Translocation" konumu) çalışamaz: kullanıcıdan Uygulamalar klasörüne taşımasını iste.
    func standaloneLocationOK() -> Bool {
        let path = Bundle.main.bundlePath
        return !(path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/"))
    }

    // İnternetten indirilen dosyalardaki "karantina" işareti, paketin içindeki programların (Java,
    // PostgreSQL…) çalışmasını engeller. Kullanıcı uygulamayı açmayı onayladığı için işaret kaldırılır.
    func prepareStandalone() -> Bool {
        let probe = bundledRuntime.appendingPathComponent("start.sh").path
        if getxattr(probe, "com.apple.quarantine", nil, 0, 0, 0) >= 0 {
            log("Karantina işareti kaldırılıyor")
            DispatchQueue.main.async { self.showStatus("İlk açılış hazırlanıyor…") }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            p.arguments = ["-dr", "com.apple.quarantine", Bundle.main.bundlePath]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
        let code = runScript("hazirla.sh", wait: true, in: bundledRuntime)
        log("hazirla.sh bitti, kod \(code)")
        return code == 0
    }

    // MARK: Servisleri başlat
    func startServicesThenLoad() {
        if isStandalone && !standaloneLocationOK() {
            showStatus("Penpot'u önce Uygulamalar klasörüne sürükleyin,\nsonra oradan açın.", spinning: false)
            let a = NSAlert()
            a.messageText = "Penpot'u Uygulamalar klasörüne taşıyın"
            a.informativeText = "Penpot disk görüntüsünün (DMG) içinden ya da İndirilenler klasöründen çalışamaz. Penpot simgesini Uygulamalar klasörüne sürükleyin ve oradan açın."
            a.addButton(withTitle: "Tamam")
            a.runModal()
            NSApp.terminate(nil)
            return
        }
        DispatchQueue.global().async {
            if isStandalone && !self.prepareStandalone() {
                DispatchQueue.main.async {
                    self.showStatus("Penpot hazırlanamadı.\nAyrıntılar: \(systemFolder.path)/logs", spinning: false)
                }
                return
            }
            // Önceki oturum hâlâ kapanıyorsa bitmesini bekle (yoksa yeni oturum, kapanan servislere bağlanır)
            if stopInProgress() {
                log("Önceki oturum kapanıyor, bekleniyor")
                DispatchQueue.main.async { self.showStatus("Önceki oturum kapatılıyor…") }
                var w = 0
                while stopInProgress() && w < 240 { usleep(250_000); w += 1 }   // 60 sn sınır
                log("Önceki oturumun kapanması bitti (\(w / 4) sn)")
            }
            if !backendReady() {
                log("Servisler başlatılıyor")
                DispatchQueue.main.async { self.showStatus("Penpot başlatılıyor…") }
                _ = runScript("start.sh", wait: false)
            }
            // Arayüzü Java sunucusunu beklemeden yükle: sayfa ve 25 MB'lık uygulama kodu sunucu açılırken
            // yüklenir; proxy, API isteklerini sunucu hazır olana kadar kendisi bekletir.
            var w = 0
            while !frontendReady() && w < 240 { usleep(100_000); w += 1 }   // 24 sn sınır
            DispatchQueue.main.async {
                log("Arayüz yükleniyor (sunucu hazır: \(backendReady() ? "evet" : "hayır"))")
                self.webView.load(URLRequest(url: penpotURL))
            }
            var waited = 0
            while !backendReady() && waited < 720 { usleep(250_000); waited += 1 }   // 180 sn sınır
            if backendReady() {
                log("Servisler hazır")
                // Güvenlik: Penpot başlığı değiştirmezse de (beklenmedik bir sayfa) birkaç sn sonra göster
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.revealWebView() }
            } else {
                log("Servisler zamanında açılmadı")
                DispatchQueue.main.async {
                    self.webView.isHidden = true
                    self.showStatus("Penpot başlatılamadı.\nAyrıntılar: \(systemFolder.path)/logs/backend.log", spinning: false)
                }
            }
        }
    }

    // MARK: Gezinme
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log("Sayfa yüklendi: \(webView.url?.absoluteString ?? "")")
        // Gösterme işi revealWebView'de: Penpot arayüzünü çizdiğinde (başlık değişince) yapılır
        if revealed { webView.isHidden = false }
    }

    // Web görünümünü yumuşak bir geçişle göster, yükleme ekranını kaldır (yalnızca bir kez)
    var revealed = false
    func revealWebView() {
        guard !revealed, !stopping else { return }
        revealed = true
        log("Arayüz gösterildi")
        webView.alphaValue = 0
        webView.isHidden = false
        loadingLabel.isHidden = true; spinner.isHidden = true; spinner.stopAnimation(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            webView.animator().alphaValue = 1
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log("Sayfa yüklenemedi: \(error.localizedDescription)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { webView.load(URLRequest(url: penpotURL)) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log("Web içeriği süreci kapandı, yeniden yükleniyor")
        webView.reload()
    }

    // localhost dışındaki bağlantılar (yardım, GitHub vb.) varsayılan tarayıcıda açılır
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload { decisionHandler(.download); return }
        if let url = action.request.url, action.targetFrame?.isMainFrame ?? true,
           let host = url.host, !["localhost", "127.0.0.1"].contains(host),
           ["http", "https"].contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url); decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = response.response as? HTTPURLResponse,
           let cd = http.value(forHTTPHeaderField: "Content-Disposition"), cd.lowercased().contains("attachment") {
            decisionHandler(.download); return
        }
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    // target=_blank ve window.open: localhost ise aynı pencerede, değilse tarayıcıda
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if let host = url.host, ["localhost", "127.0.0.1"].contains(host) { webView.load(action.request) }
            else if url.scheme == "blob" || url.scheme == "data" { webView.load(action.request) }
            else { NSWorkspace.shared.open(url) }
        }
        return nil
    }

    // MARK: İndirmeler (dışa aktarma) -> İndirilenler klasörü
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var dest = dir.appendingPathComponent(suggestedFilename)
        let base = dest.deletingPathExtension().lastPathComponent, ext = dest.pathExtension
        var i = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"); i += 1
        }
        log("İndiriliyor: \(dest.lastPathComponent)")
        objc_setAssociatedObject(download, &downloadKey, dest, .OBJC_ASSOCIATION_RETAIN)
        completionHandler(dest)
    }
    func downloadDidFinish(_ download: WKDownload) {
        if let dest = objc_getAssociatedObject(download, &downloadKey) as? URL {
            log("İndirildi: \(dest.path)")
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        log("İndirme başarısız: \(error.localizedDescription)")
    }

    // MARK: Dosya seçme, uyarı pencereleri
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { r in completionHandler(r == .OK ? panel.urls : nil) }
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "Tamam")
        a.beginSheetModal(for: window) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "Tamam"); a.addButton(withTitle: "Vazgeç")
        a.beginSheetModal(for: window) { r in completionHandler(r == .alertFirstButtonReturn) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = NSAlert(); a.messageText = prompt; a.addButton(withTitle: "Tamam"); a.addButton(withTitle: "Vazgeç")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24)); field.stringValue = defaultText ?? ""
        a.accessoryView = field
        a.beginSheetModal(for: window) { r in completionHandler(r == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    // MARK: Tanılama mesajları
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if let d = message.body as? [String: Any] { log("\(d["kind"] ?? "?"): \(d["msg"] ?? "")") }
    }

    // MARK: Kapanış: pencere kapanınca uygulama kapanır, servisler durdurulur
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Kırmızı kapat düğmesi: uygulamadan çıkışı başlatır (servisler arka planda durdurulur)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !stopping { NSApp.terminate(nil) }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if stopping { return .terminateNow }
        stopping = true
        // Anında kapanış: pencere hemen kaybolur, servisleri stop.sh arka planda durdurur.
        // Hemen yeniden açılırsa uygulama, stop.sh'nin kilidi (data/stopping.lock) kalkana kadar bekler.
        log("Uygulama kapanıyor, servisler arka planda durduruluyor")
        window.orderOut(nil)
        if FileManager.default.fileExists(atPath: systemFolder.appendingPathComponent("stop.sh").path) {
            _ = runScript("stop.sh", wait: false)
        }
        return .terminateNow
    }

    // MARK: Menü
    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Penpot Hakkında", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Penpot'u Gizle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Diğerlerini Gizle", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Penpot'tan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // Düzen menüsü: WKWebView'da kopyala/yapıştır kısayolları için gerekli
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Düzen")
        edit.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "Görünüm")
        view.addItem(withTitle: "Yeniden Yükle", action: #selector(reloadPage), keyEquivalent: "r").target = self
        view.addItem(withTitle: "Ana Sayfa", action: #selector(goHome), keyEquivalent: "").target = self
        view.addItem(.separator())
        let fs = view.addItem(withTitle: "Tam Ekran", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f"); fs.keyEquivalentModifierMask = [.command, .control]
        viewItem.submenu = view

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Pencere")
        win.addItem(withTitle: "Küçült", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Yakınlaştır", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        winItem.submenu = win
        NSApp.windowsMenu = win

        NSApp.mainMenu = main
    }

    @objc func reloadPage() { webView.reload() }
    @objc func goHome() { webView.load(URLRequest(url: penpotURL)) }

    // Dock ikonuna tıklanınca pencereyi geri getir
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if stopping {
            relaunchAfterStop = true
            showStatus("Penpot kapatılıyor… Ardından yeniden açılacak.")
            window.makeKeyAndOrderFront(nil)
            return false
        }
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }
}

var downloadKey: UInt8 = 0

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
