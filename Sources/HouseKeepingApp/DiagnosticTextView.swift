import AppKit
import HouseKeeping

final class DiagnosticTextView: NSTextView {
    private var highlightedText: String?
    private var tokens: [SyntaxToken] = []
    private var diagnostics: [EditorDiagnostic] = []
    private var hoverTrackingArea: NSTrackingArea?

    func decorate(diagnostics: [EditorDiagnostic], force: Bool = false) {
        guard let layoutManager else { return }
        guard force || highlightedText != string || self.diagnostics != diagnostics else { return }
        if highlightedText != string {
            highlightedText = string
            tokens = YAMLSyntax.tokens(in: string)
        }
        self.diagnostics = diagnostics
        toolTip = nil
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        for attribute: NSAttributedString.Key in [.foregroundColor, .underlineStyle, .underlineColor] {
            layoutManager.removeTemporaryAttribute(attribute, forCharacterRange: fullRange)
        }
        for token in tokens {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: color(for: token.kind), forCharacterRange: token.range)
        }
        for diagnostic in diagnostics where diagnostic.range.length > 0 && NSMaxRange(diagnostic.range) <= fullRange.length {
            layoutManager.addTemporaryAttributes([
                .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                .underlineColor: diagnostic.severity == .error ? NSColor.systemRed : NSColor.systemOrange,
            ], forCharacterRange: diagnostic.range)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        decorate(diagnostics: diagnostics, force: true)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard let layoutManager, let textContainer else { return }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        let index = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        let matches = diagnostics.filter { NSLocationInRange(index, $0.range) }
        toolTip = matches.isEmpty ? nil : matches.map(\.message).joined(separator: "\n")
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        toolTip = nil
    }

    override func insertTab(_: Any?) {
        insertText("  ", replacementRange: selectedRange())
    }

    private func color(for kind: SyntaxToken.Kind) -> NSColor {
        switch kind {
        case .key, .number, .literal, .anchor: .controlAccentColor
        case .comment: .secondaryLabelColor
        case .punctuation: .tertiaryLabelColor
        case .string: .textColor
        }
    }
}
