import Foundation
import Yams

/// In-process editor diagnostics, using the same decoder and validation as the CLI.
public enum ConfigDiagnostics {
    public static func analyze(_ text: String) -> [EditorDiagnostic] {
        let source = YAMLSource(text)
        do {
            guard let root = try Yams.compose(yaml: text) else {
                return [source.diagnostic("Add a configuration with version, global, and rules.", at: nil)]
            }
            var diagnostics = ConfigSchema.diagnostics(in: root, source: source)
            do {
                // Decode from the original text to retain Yams' alias/merge handling.
                let config = try YAMLDecoder().decode(Config.self, from: text)
                diagnostics += ConfigLoader().validationIssues(config).map { issue in
                    source.diagnostic(issue.message, at: source.node(at: issue.path, in: root).mark)
                }
            } catch let error as DecodingError {
                let context = context(for: error)
                let path = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }
                diagnostics.append(source.diagnostic(
                    ConfigLoader().describeDecodingError(error),
                    at: source.node(at: path, in: root).mark,
                ))
            }
            return diagnostics.sorted { $0.range.location < $1.range.location }
        } catch let error as YamlError {
            return syntaxDiagnostics(error, source: source)
        } catch {
            return [source.diagnostic(String(describing: error), at: nil)]
        }
    }

    private static func context(for error: DecodingError) -> DecodingError.Context {
        switch error {
        case let .keyNotFound(_, context), let .typeMismatch(_, context), let .valueNotFound(_, context),
             let .dataCorrupted(context): context
        @unknown default: .init(codingPath: [], debugDescription: "Invalid configuration")
        }
    }

    private static func syntaxDiagnostics(_ error: YamlError, source: YAMLSource) -> [EditorDiagnostic] {
        switch error {
        case let .scanner(context, problem, mark, _), let .parser(context, problem, mark, _),
             let .composer(context, problem, mark, _):
            let description = context.map { "\($0.text): \(problem)" } ?? problem
            return [source.diagnostic(description, at: mark)]
        case let .duplicatedKeysInMapping(duplicates, _):
            return duplicates.flatMap { key, nodes in
                nodes.map { source.diagnostic("Duplicate key '\(key.string ?? "")'.", at: $0.mark) }
            }.sorted { $0.range.location < $1.range.location }
        default:
            return [source.diagnostic(error.description, at: nil)]
        }
    }
}
