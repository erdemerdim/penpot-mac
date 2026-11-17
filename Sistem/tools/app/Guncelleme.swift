// Sürüm bilgisi ve güncelleme bildirimi (yalnızca DMG ile dağıtılan uygulamada etkin).
//
// Info.plist anahtarları (build.sh yazar):
//   CFBundleShortVersionString  uygulamanın sürümü, ör. 1.0.0 (GitHub Release etiketi v1.0.0 ile aynı)
//   PenpotVersion               içindeki Penpot sürümü, ör. 2.18.7
//   PenpotUpdateRepo            "kullanıcı/depo"; yoksa güncelleme denetimi kapalıdır (kurulum klasörü sürümü)
//
// Denetim: https://api.github.com/repos/<depo>/releases/latest (kimlik doğrulamasız; depo açık olmalı).
// Ağdan en fazla günde bir kez sorulur; bulunan son sürüm saklanır ve "Daha Sonra" denirse her
// açılışta yeniden hatırlatılır. "Bu Sürümü Atla" o sürümü bir daha göstermez. İnternet yoksa sessiz geçer.
import AppKit

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
let penpotVersion = Bundle.main.object(forInfoDictionaryKey: "PenpotVersion") as? String
let updateRepo = Bundle.main.object(forInfoDictionaryKey: "PenpotUpdateRepo") as? String

var versionLine: String {
    penpotVersion.map { "Sürüm \(appVersion) (Penpot \($0))" } ?? "Sürüm \(appVersion)"
}

/// "v1.2.3" / "1.2" gibi sürümleri sayısal karşılaştırır: a > b ise true
func isNewer(_ a: String, than b: String) -> Bool {
    func parts(_ s: String) -> [Int] {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".")
            .map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }
    let x = parts(a), y = parts(b)
    for i in 0..<max(x.count, y.count) {
        let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
        if p != q { return p > q }
    }
    return false
}

final class UpdateChecker {
    struct Release { let tag: String; let notes: String; let url: URL }

    private let d = UserDefaults.standard
    private let kLastCheck = "guncelleme.sonDenetim"
    private let kTag = "guncelleme.sonSurum", kNotes = "guncelleme.notlar", kURL = "guncelleme.adres"
    private let kSkip = "guncelleme.atlanan"
    private var showing = false

    var enabled: Bool { updateRepo != nil }

    private var cached: Release? {
        guard let t = d.string(forKey: kTag), let u = d.string(forKey: kURL).flatMap(URL.init(string:)) else { return nil }
        return Release(tag: t, notes: d.string(forKey: kNotes) ?? "", url: u)
    }

    /// Açılışta: önce saklanan bilgiyle hatırlat, sonra (günde en fazla bir kez) ağdan denetle.
    func checkOnLaunch() {
        guard enabled else { return }
        if let r = cached, isNewer(r.tag, than: appVersion), d.string(forKey: kSkip) != r.tag {
            log("Güncelleme hatırlatması: \(r.tag)")
            present(r, manual: false)
            return
        }
        let last = d.double(forKey: kLastCheck)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        fetch { [weak self] r in
            guard let self = self, let r = r else { return }
            if isNewer(r.tag, than: appVersion), self.d.string(forKey: self.kSkip) != r.tag { self.present(r, manual: false) }
        }
    }

    /// Menüden "Güncellemeleri Denetle…": her zaman ağa sorar, sonucu her durumda söyler.
    func checkManually() {
        guard enabled else { return }
        fetch { [weak self] r in
            guard let self = self else { return }
            guard let r = r else {
                self.info("Güncellemeler denetlenemedi", "İnternet bağlantınızı kontrol edip yeniden deneyin.")
                return
            }
            if isNewer(r.tag, than: appVersion) { self.present(r, manual: true) }
            else { self.info("Penpot güncel", "\(versionLine) en son sürüm.") }
        }
    }

    private func fetch(_ done: @escaping (Release?) -> Void) {
        guard let repo = updateRepo, let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { done(nil); return }
        var req = URLRequest(url: api); req.timeoutInterval = 10
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            var rel: Release?
            if let self = self, (resp as? HTTPURLResponse)?.statusCode == 200, let data = data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = j["tag_name"] as? String, let page = (j["html_url"] as? String).flatMap(URL.init(string:)) {
                rel = Release(tag: tag, notes: j["body"] as? String ?? "", url: page)
                self.d.set(Date().timeIntervalSince1970, forKey: self.kLastCheck)
                self.d.set(tag, forKey: self.kTag); self.d.set(rel!.notes, forKey: self.kNotes)
                self.d.set(page.absoluteString, forKey: self.kURL)
                log("Güncelleme denetimi: son sürüm \(tag), yüklü \(appVersion)")
            } else {
                log("Güncelleme denetimi yapılamadı (kod \((resp as? HTTPURLResponse)?.statusCode ?? 0))")
            }
            DispatchQueue.main.async { done(rel) }
        }.resume()
    }

    /// Release notlarını sade metne çevirip kısaltır
    private func shortNotes(_ md: String) -> String {
        var t = md.replacingOccurrences(of: "\r", with: "")
        for s in ["**", "__", "`", "### ", "## ", "# "] { t = t.replacingOccurrences(of: s, with: "") }
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "\n- ", with: "\n• ")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 500 ? String(t.prefix(500)) + "…" : t
    }

    private func present(_ r: Release, manual: Bool) {
        guard !showing else { return }
        showing = true
        let a = NSAlert()
        a.messageText = "Yeni sürüm hazır (\(r.tag))"
        let notes = shortNotes(r.notes)
        a.informativeText = "Yüklü sürüm: \(appVersion)\n\n" + (notes.isEmpty ? "" : notes + "\n\n")
            + "İndirdikten sonra Penpot'u kapatın ve yeni sürümü Uygulamalar klasörüne sürükleyin. Tasarımlarınız korunur."
        a.addButton(withTitle: "İndir")
        a.addButton(withTitle: "Daha Sonra")
        a.addButton(withTitle: "Bu Sürümü Atla")
        let resp = a.runModal()
        showing = false
        switch resp {
        case .alertFirstButtonReturn:
            log("Güncelleme: İndir (\(r.tag))"); NSWorkspace.shared.open(r.url)
        case .alertThirdButtonReturn:
            log("Güncelleme: atlandı (\(r.tag))"); d.set(r.tag, forKey: kSkip)
        default:
            log("Güncelleme: daha sonra (\(r.tag))")
        }
    }

    private func info(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.addButton(withTitle: "Tamam")
        a.runModal()
    }
}

let updateChecker = UpdateChecker()
