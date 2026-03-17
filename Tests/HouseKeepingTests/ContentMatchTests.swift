import Foundation
@testable import HouseKeeping
import PDFKit
import Testing

@Test func contentMatchesPlainText() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("notes.txt")
    try "This document is CONFIDENTIAL and should not be shared.".write(to: file, atomically: true, encoding: .utf8)

    let introspector = FileIntrospector()
    #expect(introspector.contentMatches(url: file, pattern: "CONFIDENTIAL", maxSize: 1_000_000))
    #expect(!introspector.contentMatches(url: file, pattern: "SECRET", maxSize: 1_000_000))
}

@Test func contentMatchesPlainTextRegex() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("log.txt")
    try "Error code: 404\nWarning code: 200\n".write(to: file, atomically: true, encoding: .utf8)

    let introspector = FileIntrospector()
    #expect(introspector.contentMatches(url: file, pattern: "Error code: \\d+", maxSize: 1_000_000))
    #expect(!introspector.contentMatches(url: file, pattern: "Error code: \\d{5}", maxSize: 1_000_000))
}

@Test func contentMatchesRespectsMaxSize() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("big.txt")
    let content = String(repeating: "hello ", count: 1000)
    try content.write(to: file, atomically: true, encoding: .utf8)

    let introspector = FileIntrospector()
    // File is ~6000 bytes; maxSize of 100 should reject it
    #expect(!introspector.contentMatches(url: file, pattern: "hello", maxSize: 100))
    // maxSize large enough should allow it
    #expect(introspector.contentMatches(url: file, pattern: "hello", maxSize: 1_000_000))
}

@Test func contentMatchesNonexistentFile() {
    let introspector = FileIntrospector()
    let fake = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)/nonexistent.txt")
    #expect(!introspector.contentMatches(url: fake, pattern: "anything", maxSize: 1_000_000))
}

@Test func contentMatchesPDF() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let pdfFile = dir.appendingPathComponent("test.pdf")

    let pdfData = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else {
        Issue.record("Failed to create PDF context")
        return
    }

    context.beginPage(mediaBox: &mediaBox)
    let text = "This invoice contains SENSITIVE financial data" as NSString
    let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
    ]
    let attrString = NSAttributedString(string: text as String, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attrString)
    context.textPosition = CGPoint(x: 72, y: 700)
    CTLineDraw(line, context)
    context.endPage()
    context.closePDF()

    try pdfData.write(to: pdfFile)

    let introspector = FileIntrospector()
    #expect(introspector.contentMatches(url: pdfFile, pattern: "SENSITIVE", maxSize: 10_000_000))
    #expect(introspector.contentMatches(url: pdfFile, pattern: "financial", maxSize: 10_000_000))
    #expect(!introspector.contentMatches(url: pdfFile, pattern: "CONFIDENTIAL", maxSize: 10_000_000))
}

@Test func contentMatchesBinaryFileReturnsFalse() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let file = dir.appendingPathComponent("binary.bin")
    // Write invalid UTF-8 bytes
    let bytes: [UInt8] = [0xFF, 0xFE, 0x00, 0x01, 0x80, 0x81, 0xC0, 0xC1]
    try Data(bytes).write(to: file)

    let introspector = FileIntrospector()
    #expect(!introspector.contentMatches(url: file, pattern: ".*", maxSize: 1_000_000))
}
