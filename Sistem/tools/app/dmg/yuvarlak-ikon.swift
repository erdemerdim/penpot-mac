// Tam kare (köşeleri keskin) Penpot simgesini macOS uygulama simgesi biçimine getirir:
// 1024'lük tuvalde 824'lük yuvarlatılmış kare, hafif gölge (Apple simge ızgarası).
// Kullanım: swift yuvarlak-ikon.swift <kaynak-1024.png> <çıktı-1024.png>
import AppKit

let a = CommandLine.arguments
guard a.count == 3, let src = NSImage(contentsOfFile: a[1]) else { print("kullanım: yuvarlak-ikon.swift <kaynak.png> <çıktı.png>"); exit(1) }
let S = 1024.0, body = 824.0, radius = 185.4
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: S, height: S)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: (S - body) / 2, y: (S - body) / 2 + 10, width: body, height: body)   // gölge için biraz yukarıda
let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// Gölge
NSGraphicsContext.saveGraphicsState()
let sh = NSShadow(); sh.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.35); sh.shadowBlurRadius = 18; sh.shadowOffset = NSSize(width: 0, height: -10)
sh.set(); NSColor.black.setFill(); shape.fill()
NSGraphicsContext.restoreGraphicsState()

// Simge içeriği yuvarlak kareye kırpılır
NSGraphicsContext.saveGraphicsState()
shape.addClip()
src.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
// İnce kenar çizgisi: koyu zeminde simgenin sınırı belli olsun
NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
shape.lineWidth = 3; shape.stroke()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
