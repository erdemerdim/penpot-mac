// Penpot exporter için pdfunite karşılığı (macOS PDFKit).
// Kullanım: pdfunite girdi1.pdf girdi2.pdf ... çıktı.pdf
// Derleme: swiftc -O pdfunite.swift -o ../bin/pdfunite
import Foundation
import PDFKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    FileHandle.standardError.write("Usage: pdfunite input1.pdf [input2.pdf ...] output.pdf\n".data(using: .utf8)!)
    exit(1)
}
let output = args.last!
let out = PDFDocument()
for input in args.dropLast() {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: input)) else {
        FileHandle.standardError.write("pdfunite: unable to read \(input)\n".data(using: .utf8)!)
        exit(1)
    }
    for i in 0..<doc.pageCount {
        if let page = doc.page(at: i) { out.insert(page, at: out.pageCount) }
    }
}
if !out.write(to: URL(fileURLWithPath: output)) {
    FileHandle.standardError.write("pdfunite: unable to write \(output)\n".data(using: .utf8)!)
    exit(1)
}
