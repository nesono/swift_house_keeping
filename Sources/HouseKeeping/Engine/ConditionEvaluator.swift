import Foundation

public struct ConditionEvaluator: Sendable {
    private let introspector = FileIntrospector()

    public init() {}

    public func evaluate(_ condition: Condition, metadata: FileMetadata) -> Bool {
        switch condition {
        case .all(let children):
            return children.allSatisfy { evaluate($0, metadata: metadata) }
        case .any(let children):
            return children.contains { evaluate($0, metadata: metadata) }
        case .none(let children):
            return !children.contains { evaluate($0, metadata: metadata) }
        case .not(let child):
            return !evaluate(child, metadata: metadata)

        case .ageDays(let comp):
            return comp.evaluate(metadata.ageDays)
        case .ageHours(let comp):
            return comp.evaluate(metadata.ageHours)
        case .ageModifiedDays(let comp):
            return comp.evaluate(metadata.ageModifiedDays)

        case .size(let comp):
            return comp.evaluate(metadata.size)

        case .extension(let exts):
            let fileExt = metadata.ext.lowercased()
            return exts.values.contains { $0.lowercased() == fileExt }

        case .nameMatches(let pattern):
            return matches(string: metadata.name, pattern: pattern)
        case .pathMatches(let pattern):
            return matches(string: metadata.path, pattern: pattern)

        case .hasTag(let tag):
            return metadata.tags.contains(tag)
        case .tagCount(let comp):
            return comp.evaluate(Double(metadata.tags.count))

        case .downloadedFrom(let source):
            guard let downloadURL = metadata.downloadURL else { return false }
            if let pattern = source.pattern {
                return matches(string: downloadURL, pattern: pattern)
            }
            if let domain = source.domain {
                return downloadURL.contains(domain)
            }
            return false

        case .isQuarantined(let expected):
            return metadata.isQuarantined == expected
        case .quarantineAgent(let agent):
            return metadata.quarantineAgentName == agent

        case .contentMatches(let match):
            return introspector.contentMatches(
                url: metadata.url,
                pattern: match.pattern,
                maxSize: match.maxSizeBytes
            )

        case .isDirectory(let expected):
            return metadata.isDirectory == expected

        case .uti(let expectedUTI):
            return metadata.uti == expectedUTI
        }
    }

    private func matches(string: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, range: range) != nil
    }
}
