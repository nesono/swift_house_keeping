import Foundation
import Yams

public struct EditorDiagnostic: Sendable, Equatable, Identifiable {
    public enum Severity: String, Sendable {
        case error, warning
    }

    public let message: String
    public let severity: Severity
    /// UTF-16 offsets, matching NSTextView and NSAttributedString.
    public let range: NSRange
    public let line: Int
    public let column: Int

    public var id: String {
        "\(range.location):\(severity):\(message)"
    }
}

struct YAMLSource {
    let text: String
    let tokens: [SyntaxToken]
    private let lines: [NSRange]

    init(_ text: String) {
        self.text = text
        tokens = YAMLSyntax.tokens(in: text)
        let source = text as NSString
        var lines: [NSRange] = []
        var offset = 0
        while offset < source.length {
            let range = source.lineRange(for: NSRange(location: offset, length: 0))
            lines.append(range)
            offset = NSMaxRange(range)
        }
        lines.append(NSRange(location: source.length, length: 0))
        self.lines = lines
    }

    func diagnostic(_ message: String, at mark: Mark?, severity: EditorDiagnostic.Severity = .error) -> EditorDiagnostic {
        let line = max(1, min(mark?.line ?? 1, lines.count))
        let contents = (text as NSString).substring(with: lines[line - 1])
        let prefix = contents.unicodeScalars.prefix(max(0, (mark?.column ?? 1) - 1))
        let columnOffset = prefix.reduce(0) { $0 + $1.utf16.count }
        let offset = min(lines[line - 1].location + columnOffset, (text as NSString).length)
        let token = tokens.first { NSLocationInRange(offset, $0.range) }
        let range = token?.range ?? NSRange(location: offset, length: 0)
        return EditorDiagnostic(message: message, severity: severity, range: range, line: line, column: mark?.column ?? 1)
    }

    func node(at path: [String], in root: Node) -> Node {
        var node = root
        for component in path {
            if let sequence = node.sequence, let index = Int(component), sequence.indices.contains(index) {
                node = sequence[index]
            } else if let next = node[component] {
                node = next
            } else {
                break
            }
        }
        return node
    }
}
