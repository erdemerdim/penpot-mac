// DMG penceresinin arka plan görselini çizer: sol üstte Penpot logosu, simgeler arasında ok, altta yönlendirme.
// Kullanım: swift arkaplan.swift <çıktı.png> <ölçek 1|2>
// Pencere 660x420 nokta; simge merkezleri dmgbuild-ayarlari.py ile aynı olmalı: (165, 190) ve (495, 190).
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let scale = Int(args[2]) else { print("kullanım: arkaplan.swift <çıktı.png> <1|2>"); exit(1) }
let W = 660.0, H = 420.0
let iconY = 190.0                       // Finder koordinatı (üstten)
let leftX = 165.0, rightX = 495.0

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W) * scale, pixelsHigh: Int(H) * scale,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)  // 2x görselde 144 dpi: Finder doğru boyutta gösterir
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let flipY = { (y: Double) in H - y }   // Finder (üstten) -> Core Graphics (alttan)

// Zemin: açık nötr. (Finder, resimli arka planda simge altı yazıları her zaman koyu yazar;
// koyu zeminde okunmuyordu. Bu yüzden zemin açık, logo/ok/yazı koyu.)
NSColor(calibratedWhite: 0.965, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()
let glow = NSGradient(colors: [NSColor(calibratedWhite: 1, alpha: 0.9), NSColor(calibratedWhite: 1, alpha: 0)])!
glow.draw(fromCenter: NSPoint(x: W / 2, y: flipY(iconY)), radius: 0,
          toCenter: NSPoint(x: W / 2, y: flipY(iconY)), radius: 330, options: [])

// Ok: iki simgenin ortasında düz, kısa ok (gövde + açık uçlu ok başı)
let y = flipY(iconY)
let cx = (leftX + rightX) / 2, half = 38.0
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: cx - half, y: y)); arrow.line(to: NSPoint(x: cx + half, y: y))
arrow.move(to: NSPoint(x: cx + half - 22, y: y + 22)); arrow.line(to: NSPoint(x: cx + half, y: y))
arrow.line(to: NSPoint(x: cx + half - 22, y: y - 22))
arrow.lineWidth = 5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(calibratedWhite: 0, alpha: 0.38).setStroke()
arrow.stroke()

// Sol üstte yatay Penpot logosu (Penpot'un kendi logo dosyası, koyu)
let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
if let logo = NSImage(contentsOf: here.appendingPathComponent("penpot-logo.svg")) {
    let lh = 30.0, lw = lh * logo.size.width / logo.size.height
    logo.draw(in: NSRect(x: 34, y: flipY(30) - lh, width: lw, height: lh), from: .zero, operation: .sourceOver, fraction: 1)
} else { print("Uyarı: logo yüklenemedi") }

// Yazılar
func text(_ s: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, top: Double) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                            .foregroundColor: NSColor(calibratedWhite: 0, alpha: alpha), .paragraphStyle: p]
    let str = NSAttributedString(string: s, attributes: a)
    let h = str.size().height
    str.draw(in: NSRect(x: 0, y: flipY(top) - h, width: W, height: h))
}
text("Kurmak için Penpot'u Uygulamalar klasörüne sürükleyin", size: 15, weight: .medium, alpha: 0.62, top: 334)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
