import AppKit
import HouseKeeping
@testable import HouseKeepingApp
import Testing

@Test @MainActor func highlightingPreservesPlainTextAndUndo() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: true)
    let editor = try DiagnosticTextView(frame: #require(window.contentView?.bounds))
    editor.isRichText = false
    editor.allowsUndo = true
    editor.string = "version: 1\n"
    window.contentView = editor
    let undo = try #require(editor.undoManager)
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    editor.insertText("# Note\n", replacementRange: NSRange(location: (editor.string as NSString).length, length: 0))
    undo.endUndoGrouping()

    editor.decorate(diagnostics: [])
    #expect(editor.string == "version: 1\n# Note\n")
    #expect(undo.canUndo)
    undo.undo()
    editor.decorate(diagnostics: [])
    #expect(editor.string == "version: 1\n")
    undo.redo()
    editor.decorate(diagnostics: [])
    #expect(editor.string == "version: 1\n# Note\n")
}

@Test @MainActor func diagnosticUnderlinesAreTemporaryAndClearWhenFixed() throws {
    let editor = DiagnosticTextView()
    editor.string = ConfigDocument.starter.replacingOccurrences(of: "version: 1", with: "version: 2")
    let original = editor.string
    let issue = try #require(ConfigDiagnostics.analyze(editor.string).first)
    let layout = try #require(editor.layoutManager)
    editor.decorate(diagnostics: [issue])
    #expect(layout.temporaryAttribute(.underlineStyle, atCharacterIndex: issue.range.location, effectiveRange: nil) != nil)
    #expect(editor.textStorage?.attribute(.underlineStyle, at: issue.range.location, effectiveRange: nil) == nil)
    #expect(editor.string == original)

    editor.decorate(diagnostics: [])
    #expect(layout.temporaryAttribute(.underlineStyle, atCharacterIndex: issue.range.location, effectiveRange: nil) == nil)
    #expect(editor.string == original)
}
