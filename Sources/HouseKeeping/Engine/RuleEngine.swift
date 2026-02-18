import Foundation

public struct RuleMatch: Sendable {
    public let rule: Rule
    public let file: FileMetadata
}

public struct RuleEngine: Sendable {
    private let conditionEvaluator = ConditionEvaluator()
    private let introspector = FileIntrospector()

    public init() {}

    public func findMatches(rule: Rule, config: Config) throws -> [RuleMatch] {
        let expandedConfig = config.expandingPaths()
        guard let expandedRule = expandedConfig.rules.first(where: { $0.name == rule.name }) else {
            return []
        }

        var matches: [RuleMatch] = []
        let fm = FileManager.default

        for watchPath in expandedRule.watchPaths {
            let url = URL(fileURLWithPath: watchPath)

            if expandedRule.recursive {
                if let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles],
                ) {
                    for case let fileURL as URL in enumerator {
                        if let match = try evaluateFile(at: fileURL, rule: expandedRule) {
                            matches.append(match)
                        }
                    }
                }
            } else {
                let contents = try fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles],
                )
                for fileURL in contents {
                    if let match = try evaluateFile(at: fileURL, rule: expandedRule) {
                        matches.append(match)
                    }
                }
            }
        }

        return matches
    }

    public func evaluateFile(at url: URL, rule: Rule) throws -> RuleMatch? {
        let metadata = try introspector.inspect(url: url)
        if conditionEvaluator.evaluate(rule.conditions, metadata: metadata) {
            return RuleMatch(rule: rule, file: metadata)
        }
        return nil
    }

    public func evaluateSingleFile(at url: URL, rules: [Rule]) throws -> [RuleMatch] {
        let metadata = try introspector.inspect(url: url)
        return rules.compactMap { rule in
            if conditionEvaluator.evaluate(rule.conditions, metadata: metadata) {
                return RuleMatch(rule: rule, file: metadata)
            }
            return nil
        }
    }
}
