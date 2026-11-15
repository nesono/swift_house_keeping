import AppKit
import HouseKeeping
import SwiftUI

struct EditorSelection {
    let id = UUID()
    let range: NSRange
}

/// Syntax and diagnostic decoration uses temporary layout attributes, preserving plain-text undo and saving.
struct YAMLEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var diagnostics: [EditorDiagnostic] = []
    var selection: EditorSelection?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let editor = DiagnosticTextView()
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.drawsBackground = false
        editor.textColor = .textColor
        editor.textContainerInset = NSSize(width: 4, height: 6)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.setAccessibilityLabel("YAML configuration")
        editor.string = text
        editor.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        scroll.documentView = editor
        editor.decorate(diagnostics: diagnostics)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? DiagnosticTextView else { return }
        context.coordinator.text = $text
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
        editor.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        editor.decorate(diagnostics: diagnostics)
        if let selection, selection.id != context.coordinator.lastSelectionID {
            context.coordinator.lastSelectionID = selection.id
            let length = (editor.string as NSString).length
            let start = min(selection.range.location, length)
            let range = NSRange(location: start, length: min(selection.range.length, length - start))
            editor.window?.makeFirstResponder(editor)
            editor.setSelectedRange(range)
            editor.scrollRangeToVisible(range)
            editor.showFindIndicator(for: range)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var lastSelectionID: UUID?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? DiagnosticTextView else { return }
            text.wrappedValue = editor.string
            editor.decorate(diagnostics: [])
        }
    }
}
