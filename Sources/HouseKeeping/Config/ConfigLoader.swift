import Foundation
import Yams

public enum ConfigError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case parseError(String)
    case validationError([String])

    public var description: String {
        switch self {
        case let .fileNotFound(path):
            "Config file not found: \(path)"
        case let .parseError(msg):
            "Failed to parse config: \(msg)"
        case let .validationError(errors):
            "Config validation errors:\n" + errors.map { "  - \($0)" }.joined(separator: "\n")
        }
    }
}

public struct ConfigLoader: Sendable {
    public static let defaultConfigPath = "~/.config/house_keeping/config.yaml"

    public init() {}

    public func load(from path: String? = nil) throws -> Config {
        let resolvedPath = Config.expandPath(path ?? Self.defaultConfigPath)

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw ConfigError.fileNotFound(resolvedPath)
        }

        let contents = try String(contentsOfFile: resolvedPath, encoding: .utf8)
        return try parse(contents)
    }

    public func parse(_ yaml: String) throws -> Config {
        do {
            let decoder = YAMLDecoder()
            return try decoder.decode(Config.self, from: yaml)
        } catch let error as DecodingError {
            throw ConfigError.parseError(describeDecodingError(error))
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }

    public func validate(_ config: Config) -> [String] {
        validationIssues(config).map(\.message)
    }

    func validationIssues(_ config: Config) -> [ConfigValidationIssue] {
        var errors: [ConfigValidationIssue] = []

        if config.version != 1 {
            errors.append(.init(path: ["version"], message: "Unsupported config version: \(config.version) (expected 1)"))
        }

        var ruleNames = Set<String>()
        for (i, rule) in config.rules.enumerated() {
            let prefix = "rules[\(i)] (\(rule.name))"
            let path = ["rules", String(i)]
            func issue(_ field: [String], _ message: String) -> ConfigValidationIssue {
                .init(path: path + field, message: "\(prefix): \(message)")
            }

            if rule.name.isEmpty {
                errors.append(issue(["name"], "name cannot be empty"))
            }
            if !ruleNames.insert(rule.name).inserted {
                errors.append(issue(["name"], "duplicate rule name '\(rule.name)'"))
            }
            if rule.watchPaths.isEmpty {
                errors.append(issue(["watch_paths"], "watch_paths cannot be empty"))
            }
            if rule.actions.isEmpty {
                errors.append(issue(["actions"], "actions cannot be empty"))
            }

            // Validate trigger
            switch rule.trigger.type {
            case .schedule:
                if rule.trigger.interval == nil {
                    errors.append(issue(["trigger"], "schedule trigger requires 'interval'"))
                } else if rule.trigger.intervalSeconds == nil {
                    errors.append(issue(["trigger", "interval"], "invalid interval format '\(rule.trigger.interval!)'"))
                }
            case .fileChange:
                if rule.trigger.events == nil || rule.trigger.events!.isEmpty {
                    errors.append(issue(["trigger"], "file_change trigger requires 'events'"))
                }
            }

            // Validate watch paths exist
            let expanded = config.expandingPaths()
            for (index, path) in expanded.rules[i].watchPaths.enumerated() {
                var isDir: ObjCBool = false
                if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                    errors.append(issue(["watch_paths", String(index)], "watch path does not exist: \(path)"))
                } else if !isDir.boolValue {
                    errors.append(issue(["watch_paths", String(index)], "watch path is not a directory: \(path)"))
                }
            }
        }

        return errors
    }

    func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing key '\(key.stringValue)' at \(path.isEmpty ? "root" : path)"
        case let .typeMismatch(type, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch at \(path.isEmpty ? "root" : path): expected \(type) - \(context.debugDescription)"
        case let .valueNotFound(type, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing value of type \(type) at \(path.isEmpty ? "root" : path)"
        case let .dataCorrupted(context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Data corrupted at \(path.isEmpty ? "root" : path): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

struct ConfigValidationIssue {
    let path: [String]
    let message: String
}
