// "Başka uygulamada aç" köprüsü: aktar.js'in (sayfadaki sol menü kartları) gönderdiği
// dışa aktarmaları alır ve hedef uygulamada açar.
//   illustrator: SVG (görseller gömülü, varsayılan) ya da board PDF'leri tek PDF'te birleştirilir, ~/Downloads/Penpot Aktarım/ altına
//                kaydedilir ve Adobe Illustrator ile açılır.
//   figma:       birleşik SVG panoya (düz metin olarak; Figma SVG kodunu yapıştırınca vektör
//                olarak alır) kopyalanır, yedeği aynı klasöre kaydedilir ve Figma açılır.
// Figma dışarıdan dosya açtırmaya izin vermediği için son adım kullanıcının ⌘V yapmasıdır.
import AppKit
import PDFKit
import WebKit

final class AktarHandler: NSObject, WKScriptMessageHandlerWithReply {
    static let illustratorIDs = ["com.adobe.illustrator"]
    static let figmaIDs = ["com.figma.Desktop", "com.figma.desktop"]

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let d = message.body as? [String: Any], let kind = d["kind"] as? String else {
            replyHandler(["error": "Geçersiz istek"], nil); return
        }
        let name = Self.safeName(d["name"] as? String ?? "Penpot")
        do {
            switch kind {
            case "illustrator":
                if let svg = d["svg"] as? String, !svg.isEmpty {
                    // SVG (görseller gömülü): Illustrator'da en iyi sonucu veren biçim
                    let url = try Self.uniqueURL(name: name, ext: "svg")
                    try svg.data(using: .utf8)!.write(to: url)
                    log("Aktar: Illustrator için SVG -> \(url.path) (\(svg.count) karakter)")
                    open(url, appIDs: Self.illustratorIDs, appName: "Adobe Illustrator", replyHandler: replyHandler)
                    return
                }
                let pdfs = (d["pdfs"] as? [String] ?? []).compactMap { Data(base64Encoded: $0) }
                guard !pdfs.isEmpty else { throw Self.err("Dışa aktarılan PDF boş") }
                let url = try Self.saveMergedPDF(pdfs, name: name)
                log("Aktar: Illustrator için \(pdfs.count) board -> \(url.path)")
                open(url, appIDs: Self.illustratorIDs, appName: "Adobe Illustrator", replyHandler: replyHandler)
            case "figma":
                guard let svg = d["svg"] as? String, !svg.isEmpty else { throw Self.err("Dışa aktarılan SVG boş") }
                let url = try Self.uniqueURL(name: name, ext: "svg")
                try svg.data(using: .utf8)!.write(to: url)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(svg, forType: .string)
                log("Aktar: Figma için SVG panoya kopyalandı (\(svg.count) karakter), yedek \(url.path)")
                guard let app = Self.appURL(Self.figmaIDs) else {
                    // Figma masaüstü uygulaması yoksa tarayıcıda Figma açılır; SVG yine panodadır
                    NSWorkspace.shared.open(URL(string: "https://www.figma.com/files")!)
                    replyHandler(["ok": true, "web": true], nil); return
                }
                NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, error in
                    DispatchQueue.main.async {
                        replyHandler(error.map { ["error": "Figma açılamadı: \($0.localizedDescription)"] } ?? ["ok": true], nil)
                    }
                }
            default:
                replyHandler(["error": "Bilinmeyen hedef: \(kind)"], nil)
            }
        } catch {
            log("Aktar hatası: \(error.localizedDescription)")
            replyHandler(["error": error.localizedDescription], nil)
        }
    }

    private func open(_ file: URL, appIDs: [String], appName: String, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let app = Self.appURL(appIDs) else {
            NSWorkspace.shared.activateFileViewerSelecting([file])
            replyHandler(["error": "\(appName) bu Mac'te bulunamadı. Dosya İndirilenler > Penpot Aktarım klasörüne kaydedildi."], nil)
            return
        }
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: .init()) { _, error in
            DispatchQueue.main.async {
                replyHandler(error.map { ["error": "\(appName) açılamadı: \($0.localizedDescription)"] } ?? ["ok": true], nil)
            }
        }
    }

    static func appURL(_ ids: [String]) -> URL? {
        ids.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    static func saveMergedPDF(_ pdfs: [Data], name: String) throws -> URL {
        guard let out = PDFDocument(data: pdfs[0]) else { throw err("PDF okunamadı") }
        for data in pdfs.dropFirst() {
            guard let doc = PDFDocument(data: data) else { throw err("PDF okunamadı") }
            for i in 0..<doc.pageCount { if let p = doc.page(at: i) { out.insert(p, at: out.pageCount) } }
        }
        let url = try uniqueURL(name: name, ext: "pdf")
        guard out.write(to: url) else { throw err("PDF kaydedilemedi") }
        return url
    }

    static func uniqueURL(name: String, ext: String) throws -> URL {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Penpot Aktarım", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var url = dir.appendingPathComponent("\(name).\(ext)")
        var i = 2
        while FileManager.default.fileExists(atPath: url.path) { url = dir.appendingPathComponent("\(name) (\(i)).\(ext)"); i += 1 }
        return url
    }

    static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines)
        let t = s.components(separatedBy: bad).joined(separator: "_").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Penpot" : String(t.prefix(100))
    }

    static func err(_ m: String) -> NSError { NSError(domain: "Penpot", code: 1, userInfo: [NSLocalizedDescriptionKey: m]) }
}

let aktarHandler = AktarHandler()

/// Sayfaya eklenecek kullanıcı betiği (uygulama paketindeki aktar.js)
func aktarUserScript() -> WKUserScript? {
    guard let url = Bundle.main.url(forResource: "aktar", withExtension: "js"),
          let js = try? String(contentsOf: url, encoding: .utf8) else { log("aktar.js bulunamadı"); return nil }
    return WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
}
