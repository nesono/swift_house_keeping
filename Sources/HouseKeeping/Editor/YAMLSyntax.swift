import Foundation

public struct SyntaxToken: Sendable, Equatable {
    public enum Kind: Sendable {
        case key, string, number, literal, comment, punctuation, anchor
    }

    public let range: NSRange
    public let kind: Kind
}

/// A tolerant lexer: highlighting remains available while the YAML is incomplete.
public enum YAMLSyntax {
    private static let expression = try? NSRegularExpression(pattern: [
        #"(?<comment>(?<!\S)#[^\r\n]*)"#,
        #"(?<quoted>"(?:\\[\s\S]|[^"\\])*(?:"|$)|'(?:''|[^'])*(?:'|$))"#,
        #"(?<key>[\p{L}_][\p{L}\p{N}_-]*(?=[ \t]*:(?:\s|[\[\]{},]|$)))"#,
        #"(?<block>[|>][1-9+-]{0,2}(?=[ \t]*(?:#[^\r\n]*)?$))"#,
        #"(?<anchor>[&*!][\w.-]+)"#,
        #"(?<plain>[^\s\[\]{},:#"'][^\s\[\]{},:]*(?::[^\s\[\]{},]+)*|[^\s])"#,
    ].joined(separator: "|"), options: .anchorsMatchLines)

    public static func tokens(in text: String) -> [SyntaxToken] {
        let source = text as NSString
        guard let expression else { return [] }
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: source.length))
        var tokens: [SyntaxToken] = []
        var blockEnd = 0
        for match in matches {
            guard match.range.location >= blockEnd else { continue }
            var range = match.range
            let kind: SyntaxToken.Kind
            if match.range(withName: "comment").location != NSNotFound {
                kind = .comment
            } else if match.range(withName: "quoted").location != NSNotFound {
                let suffix = source.substring(from: NSMaxRange(range)).prefix { $0 == " " || $0 == "\t" || $0 == ":" }
                kind = suffix.contains(":") ? .key : .string
            } else if match.range(withName: "key").location != NSNotFound {
                kind = .key
            } else if match.range(withName: "block").location != NSNotFound {
                blockEnd = endOfBlock(in: source, startingAt: range.location)
                range.length = blockEnd - range.location
                kind = .string
            } else if match.range(withName: "anchor").location != NSNotFound {
                kind = .anchor
            } else {
                kind = scalarKind(source.substring(with: range))
            }
            tokens.append(SyntaxToken(range: range, kind: kind))
        }
        return tokens
    }

    private static func scalarKind(_ value: String) -> SyntaxToken.Kind {
        if ["true", "false", "yes", "no", "on", "off", "null", "~"].contains(value.lowercased()) {
            return .literal
        }
        if Double(value.replacingOccurrences(of: "_", with: "")) != nil {
            return .number
        }
        if [":", "-", "[", "]", "{", "}", ",", "?", "---", "..."].contains(value) {
            return .punctuation
        }
        return .string
    }

    private static func endOfBlock(in source: NSString, startingAt offset: Int) -> Int {
        let header = source.lineRange(for: NSRange(location: offset, length: 0))
        let indentation = source.substring(with: header).prefix { $0 == " " }.count
        var end = NSMaxRange(header)
        while end < source.length {
            let line = source.lineRange(for: NSRange(location: end, length: 0))
            let contents = source.substring(with: line)
            if !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               contents.prefix(while: { $0 == " " }).count <= indentation
            {
                break
            }
            end = NSMaxRange(line)
        }
        return end
    }
}
