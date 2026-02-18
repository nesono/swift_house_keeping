import Foundation

public struct ConditionEvaluator: Sendable {
    private let introspector = FileIntrospector()

    public init() {}

    public func evaluate(_ condition: Condition, metadata: FileMetadata) -> Bool {
        switch condition {
        case let .all(children):
            children.allSatisfy { evaluate($0, metadata: metadata) }
        case let .any(children):
            children.contains { evaluate($0, metadata: metadata) }
        case let .none(children):
            !children.contains { evaluate($0, metadata: metadata) }
        case let .not(child):
            !evaluate(child, metadata: metadata)
        case .ageDays, .ageHours, .ageModifiedDays, .size:
            evaluateNumeric(condition, metadata: metadata)
        case .extension, .nameMatches, .pathMatches, .hasTag, .tagCount:
            evaluateFileProperties(condition, metadata: metadata)
        case .downloadedFrom, .isQuarantined, .quarantineAgent:
            evaluateProvenance(condition, metadata: metadata)
        case .contentMatches, .isDirectory, .uti:
            evaluateContent(condition, metadata: metadata)
        }
    }

    private func evaluateNumeric(_ condition: Condition, metadata: FileMetadata) -> Bool {
        switch condition {
        case let .ageDays(comp):
            comp.evaluate(metadata.ageDays)
        case let .ageHours(comp):
            comp.evaluate(metadata.ageHours)
        case let .ageModifiedDays(comp):
            comp.evaluate(metadata.ageModifiedDays)
        case let .size(comp):
            comp.evaluate(metadata.size)
        default:
            false
        }
    }

    private func evaluateFileProperties(_ condition: Condition, metadata: FileMetadata) -> Bool {
        switch condition {
        case let .extension(exts):
            let fileExt = metadata.ext.lowercased()
            return exts.values.contains { $0.lowercased() == fileExt }
        case let .nameMatches(pattern):
            return matches(string: metadata.name, pattern: pattern)
        case let .pathMatches(pattern):
            return matches(string: metadata.path, pattern: pattern)
        case let .hasTag(tag):
            return metadata.tags.contains(tag)
        case let .tagCount(comp):
            return comp.evaluate(Double(metadata.tags.count))
        default:
            return false
        }
    }

    private func evaluateProvenance(_ condition: Condition, metadata: FileMetadata) -> Bool {
        switch condition {
        case let .downloadedFrom(source):
            guard let downloadURL = metadata.downloadURL else { return false }
            if let pattern = source.pattern {
                return matches(string: downloadURL, pattern: pattern)
            }
            if let domain = source.domain {
                return downloadURL.contains(domain)
            }
            return false
        case let .isQuarantined(expected):
            return metadata.isQuarantined == expected
        case let .quarantineAgent(agent):
            return metadata.quarantineAgentName == agent
        default:
            return false
        }
    }

    private func evaluateContent(_ condition: Condition, metadata: FileMetadata) -> Bool {
        switch condition {
        case let .contentMatches(match):
            introspector.contentMatches(
                url: metadata.url,
                pattern: match.pattern,
                maxSize: match.maxSizeBytes,
            )
        case let .isDirectory(expected):
            metadata.isDirectory == expected
        case let .uti(expectedUTI):
            metadata.uti == expectedUTI
        default:
            false
        }
    }

    private func matches(string: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, range: range) != nil
    }
}
