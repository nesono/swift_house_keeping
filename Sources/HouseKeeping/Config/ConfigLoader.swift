import Foundation
import Yams

public enum ConfigError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case parseError(String)
    case validationError([String])

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Config file not found: \(path)"
        case .parseError(let msg):
            return "Failed to parse config: \(msg)"
        case .validationError(let errors):
            return "Config validation errors:\n" + errors.map { "  - \($0)" }.joined(separator: "\n")
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
            let config = try decoder.decode(Config.self, from: yaml)
            return config
        } catch let error as DecodingError {
            throw ConfigError.parseError(describeDecodingError(error))
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }

    public func validate(_ config: Config) -> [String] {
        var errors: [String] = []

        if config.version != 1 {
            errors.append("Unsupported config version: \(config.version) (expected 1)")
        }

        var ruleNames = Set<String>()
        for (i, rule) in config.rules.enumerated() {
            let prefix = "rules[\(i)] (\(rule.name))"

            if rule.name.isEmpty {
                errors.append("\(prefix): name cannot be empty")
            }
            if !ruleNames.insert(rule.name).inserted {
                errors.append("\(prefix): duplicate rule name '\(rule.name)'")
            }
            if rule.watchPaths.isEmpty {
                errors.append("\(prefix): watch_paths cannot be empty")
            }
            if rule.actions.isEmpty {
                errors.append("\(prefix): actions cannot be empty")
            }

            // Validate trigger
            switch rule.trigger.type {
            case .schedule:
                if rule.trigger.interval == nil {
                    errors.append("\(prefix): schedule trigger requires 'interval'")
                } else if rule.trigger.intervalSeconds == nil {
                    errors.append("\(prefix): invalid interval format '\(rule.trigger.interval!)'")
                }
            case .fileChange:
                if rule.trigger.events == nil || rule.trigger.events!.isEmpty {
                    errors.append("\(prefix): file_change trigger requires 'events'")
                }
            }

            // Validate watch paths exist
            let expanded = config.expandingPaths()
            for path in expanded.rules[i].watchPaths {
                var isDir: ObjCBool = false
                if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                    errors.append("\(prefix): watch path does not exist: \(path)")
                } else if !isDir.boolValue {
                    errors.append("\(prefix): watch path is not a directory: \(path)")
                }
            }
        }

        return errors
    }

    private func describeDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing key '\(key.stringValue)' at \(path.isEmpty ? "root" : path)"
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch at \(path.isEmpty ? "root" : path): expected \(type) - \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing value of type \(type) at \(path.isEmpty ? "root" : path)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Data corrupted at \(path.isEmpty ? "root" : path): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}
