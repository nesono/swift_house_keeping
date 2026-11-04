import Foundation
@testable import HouseKeeping
import Testing

private func withConfigURL(_ test: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try test(directory.appendingPathComponent("nested/config.yaml"))
}

@Test func newDocumentDoesNotWriteUntilSaved() throws {
    try withConfigURL { url in
        var document = try ConfigDocument(path: url.path)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(document.isDirty)
        #expect(try document.validate().rules.isEmpty)
        try document.save()
        #expect(!document.isDirty)
        #expect(try ConfigLoader().load(from: url.path).rules.isEmpty)
    }
}

@Test func documentPreservesCommentsAndFormatting() throws {
    try withConfigURL { url in
        var document = try ConfigDocument(path: url.path)
        document.text = "# My configuration\n" + document.text + "\n# Keep this comment\n"
        try document.save()
        let reopened = try ConfigDocument(path: url.path)
        #expect(reopened.text == document.text)
        #expect(!reopened.isDirty)
    }
}

@Test func invalidEditsLeaveSavedConfigurationIntact() throws {
    try withConfigURL { url in
        var document = try ConfigDocument(path: url.path)
        try document.save()
        let original = try Data(contentsOf: url)
        document.text = "rules: ["
        #expect(throws: ConfigError.self) { try document.save() }
        #expect(try Data(contentsOf: url) == original)
        document.text = ConfigDocument.starter.replacingOccurrences(of: "version: 1", with: "version: 2")
        #expect(throws: ConfigError.self) { try document.save() }
        #expect(try Data(contentsOf: url) == original)
    }
}

@Test func documentDetectsExternalChangesIncludingAfterDraftRestoration() throws {
    try withConfigURL { url in
        var document = try ConfigDocument(path: url.path)
        try document.save()
        document.text += "# Unsaved draft\n"
        let draft = try JSONEncoder().encode(document)
        let external = ConfigDocument.starter + "# External edit\n"
        try external.write(to: url, atomically: true, encoding: .utf8)
        var restored = try JSONDecoder().decode(ConfigDocument.self, from: draft)
        #expect(restored.text == document.text)
        #expect(throws: DocumentError.self) { try restored.save() }
        #expect(try String(contentsOf: url, encoding: .utf8) == external)
    }
}

@Test func documentDetectsNewlyCreatedOrDeletedFile() throws {
    try withConfigURL { url in
        var first = try ConfigDocument(path: url.path)
        var second = try ConfigDocument(path: url.path)
        try first.save()
        #expect(throws: DocumentError.self) { try second.save() }
        try FileManager.default.removeItem(at: url)
        first.text += "# Draft after deletion\n"
        #expect(throws: DocumentError.self) { try first.save() }
    }
}

@Test func editingSymlinkPreservesLink() throws {
    try withConfigURL { url in
        var original = try ConfigDocument(path: url.path)
        try original.save()
        let link = url.deletingLastPathComponent().appendingPathComponent("linked.yaml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        var document = try ConfigDocument(path: link.path)
        document.text += "# Through the link\n"
        try document.save()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == url.path)
        #expect(try String(contentsOf: url, encoding: .utf8) == document.text)
    }
}
