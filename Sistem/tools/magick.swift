// Penpot için küçük bir ImageMagick yerine geçen program (macOS ImageIO kullanır).
// Penpot backend'inin kullandığı komutları destekler:
//   magick identify -format "<biçim>" <dosya>        (%w %h %[magick] %[EXIF:Orientation] \n)
//   magick <girdi> -auto-orient -strip -thumbnail WxH> -quality Q <çıktı>
//   magick <girdi> -auto-orient -strip -thumbnail WxH^ -gravity center -extent WxH -quality Q <çıktı>
// Derleme: swiftc -O magick.swift -o ../bin/magick
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func openSource(_ path: String) -> CGImageSource {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          CGImageSourceGetCount(src) > 0,
          CGImageSourceGetType(src) != nil else {
        fail("magick: unable to read image: \(path)")
    }
    return src
}

func props(_ src: CGImageSource) -> [CFString: Any] {
    (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
}

func magickName(_ src: CGImageSource) -> String {
    let t = (CGImageSourceGetType(src) as String?) ?? ""
    switch t {
    case UTType.png.identifier: return "PNG"
    case UTType.jpeg.identifier: return "JPEG"
    case UTType.gif.identifier: return "GIF"
    case "org.webmproject.webp": return "WEBP"
    case UTType.tiff.identifier: return "TIFF"
    case UTType.heic.identifier: return "HEIC"
    case UTType.bmp.identifier: return "BMP"
    default: return UTType(t)?.preferredFilenameExtension?.uppercased() ?? "UNKNOWN"
    }
}

func identify(_ args: [String]) {
    var format = "%m %wx%h\n"
    var path: String?
    var i = 0
    while i < args.count {
        if args[i] == "-format", i + 1 < args.count { format = args[i + 1]; i += 2; continue }
        if args[i].hasPrefix("-") { i += 1; continue }
        path = args[i]; i += 1
    }
    guard let p = path else { fail("magick identify: no input file") }
    let src = openSource(p)
    let pr = props(src)
    let w = (pr[kCGImagePropertyPixelWidth] as? Int).map(String.init) ?? "0"
    let h = (pr[kCGImagePropertyPixelHeight] as? Int).map(String.init) ?? "0"
    var orient = ""
    if let o = pr[kCGImagePropertyOrientation] as? Int { orient = String(o) }
    let out = format
        .replacingOccurrences(of: "%[magick]", with: magickName(src))
        .replacingOccurrences(of: "%[EXIF:Orientation]", with: orient)
        .replacingOccurrences(of: "%m", with: magickName(src))
        .replacingOccurrences(of: "%w", with: w)
        .replacingOccurrences(of: "%h", with: h)
        .replacingOccurrences(of: "\\n", with: "\n")
    FileHandle.standardOutput.write(out.data(using: .utf8)!)
}

func parseGeometry(_ g: String) -> (Int, Int, Character?) {
    var s = g
    var flag: Character? = nil
    if let last = s.last, "><^!".contains(last) { flag = last; s.removeLast() }
    let parts = s.split(separator: "x").map { Int($0) ?? 0 }
    guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { fail("magick: invalid geometry \(g)") }
    return (parts[0], parts[1], flag)
}

func convert(_ args: [String]) {
    guard args.count >= 2 else { fail("magick: usage: magick input [options] output") }
    let input = args[0]
    let output = args[args.count - 1]
    let opts = Array(args[1..<(args.count - 1)])
    var autoOrient = false
    var thumb: (Int, Int, Character?)?
    var extent: (Int, Int)?
    var quality = 85
    var i = 0
    while i < opts.count {
        switch opts[i] {
        case "-auto-orient": autoOrient = true
        case "-strip": break
        case "-thumbnail", "-resize":
            guard i + 1 < opts.count else { fail("magick: missing geometry") }
            thumb = parseGeometry(opts[i + 1]); i += 1
        case "-extent":
            guard i + 1 < opts.count else { fail("magick: missing extent") }
            let g = parseGeometry(opts[i + 1]); extent = (g.0, g.1); i += 1
        case "-gravity": i += 1 // yalnızca center destekleniyor
        case "-quality":
            guard i + 1 < opts.count else { fail("magick: missing quality") }
            quality = Int(opts[i + 1]) ?? 85; i += 1
        default: break
        }
        i += 1
    }

    let src = openSource(input)
    let pr = props(src)
    let pw = pr[kCGImagePropertyPixelWidth] as? Int ?? 0
    let ph = pr[kCGImagePropertyPixelHeight] as? Int ?? 0
    // İlk kare; -auto-orient istendiyse EXIF yönü uygulanmış hali
    let loadOpts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: autoOrient,
        kCGImageSourceThumbnailMaxPixelSize: max(pw, ph, 1),
        kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, loadOpts as CFDictionary) else {
        fail("magick: unable to decode image: \(input)")
    }
    let iw = Double(img.width), ih = Double(img.height)

    var dw = iw, dh = ih
    if let (tw, th, flag) = thumb {
        let sx = Double(tw) / iw, sy = Double(th) / ih
        var s: Double
        switch flag {
        case "^": s = max(sx, sy)
        case ">": s = min(1.0, min(sx, sy))
        case "<": s = max(1.0, min(sx, sy))
        default: s = min(sx, sy)
        }
        if flag == "!" { dw = Double(tw); dh = Double(th) } else { dw = (iw * s).rounded(); dh = (ih * s).rounded() }
        dw = max(dw, 1); dh = max(dh, 1)
    }
    let cw = extent.map { Double($0.0) } ?? dw
    let ch = extent.map { Double($0.1) } ?? dh

    let ext = (output as NSString).pathExtension.lowercased()
    let isJPEG = ext == "jpg" || ext == "jpeg"
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: Int(cw), height: Int(ch), bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("magick: unable to create canvas")
    }
    ctx.interpolationQuality = .high
    if isJPEG {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: cw, height: ch))
    }
    // gravity center
    ctx.draw(img, in: CGRect(x: (cw - dw) / 2, y: (ch - dh) / 2, width: dw, height: dh))
    guard let outImg = ctx.makeImage() else { fail("magick: unable to render image") }

    let type: String
    switch ext {
    case "jpg", "jpeg": type = UTType.jpeg.identifier
    case "gif": type = UTType.gif.identifier
    default: type = UTType.png.identifier // png (ve yazılamayan webp için yedek)
    }
    let url = URL(fileURLWithPath: output) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, type as CFString, 1, nil) else {
        fail("magick: unable to write \(output)")
    }
    var dprops: [CFString: Any] = [:]
    if isJPEG { dprops[kCGImageDestinationLossyCompressionQuality] = Double(max(1, min(quality, 100))) / 100.0 }
    CGImageDestinationAddImage(dest, outImg, dprops as CFDictionary)
    if !CGImageDestinationFinalize(dest) { fail("magick: failed to write \(output)") }
}

var argv = Array(CommandLine.arguments.dropFirst())
if argv.first == "convert" { argv.removeFirst() }
if argv.first == "identify" {
    identify(Array(argv.dropFirst()))
} else if argv.first == "-version" || argv.first == "--version" {
    print("Version: ImageMagick-compatible shim for Penpot (macOS ImageIO)")
} else {
    convert(argv)
}
