import Foundation
import Yams

/// Unknown-key hints supplement Codable, which otherwise silently ignores misspelled keys.
enum ConfigSchema {
    enum Section {
        case root, global, rule, trigger, condition, action, comparison, size, download, content, rename, notify

        var keys: Set<String> {
            switch self {
            case .root: ["version", "global", "rules"]
            case .global: ["log_level", "log_file", "state_file"]
            case .rule: ["name", "description", "enabled", "priority", "trigger", "watch_paths", "recursive", "conditions", "actions"]
            case .trigger: ["type", "interval", "events"]
            case .condition:
                ["all", "any", "none", "not", "age_days", "age_hours", "age_modified_days", "size", "extension", "name_matches",
                 "path_matches", "has_tag", "tag_count", "downloaded_from", "is_quarantined", "quarantine_agent", "content_matches",
                 "is_directory", "uti", "is_duplicate"]
            case .action:
                ["set_tag", "remove_tag", "clear_tags", "set_color_label", "move", "copy", "trash", "delete", "rename",
                 "run_script", "notify", "log", "remove_quarantine"]
            case .comparison: ["gt", "lt", "gte", "lte", "eq"]
            case .size: ["gt", "lt", "gte", "lte", "between"]
            case .download: ["pattern", "domain"]
            case .content: ["pattern", "max_size"]
            case .rename: ["pattern", "replacement"]
            case .notify: ["title", "body"]
            }
        }

        func child(for key: String) -> Section? {
            switch (self, key) {
            case (.root, "global"): .global
            case (.root, "rules"): .rule
            case (.rule, "trigger"): .trigger
            case (.rule, "conditions"), (.condition, "all"), (.condition, "any"), (.condition, "none"), (.condition, "not"): .condition
            case (.rule, "actions"): .action
            case (.condition, "age_days"), (.condition, "age_hours"), (.condition, "age_modified_days"), (.condition, "tag_count"): .comparison
            case (.condition, "size"): .size
            case (.condition, "downloaded_from"): .download
            case (.condition, "content_matches"): .content
            case (.action, "rename"): .rename
            case (.action, "notify"): .notify
            default: nil
            }
        }
    }

    static func diagnostics(in node: Node, source: YAMLSource, section: Section = .root, depth: Int = 0) -> [EditorDiagnostic] {
        guard depth < 128 else { return [] }
        if let sequence = node.sequence {
            return sequence.flatMap { Self.diagnostics(in: $0, source: source, section: section, depth: depth + 1) }
        }
        guard let mapping = node.mapping else { return [] }
        var diagnostics: [EditorDiagnostic] = []
        var seen: Set<String> = []
        for (key, value) in mapping {
            guard let name = key.string else { continue }
            if !seen.insert(name).inserted {
                diagnostics.append(source.diagnostic("Duplicate key '\(name)'.", at: key.mark))
            }
            if name == "<<" { continue } // YAML merge keys are handled by the decoder.
            if !section.keys.contains(name) {
                let suggestion = section.keys.sorted().min { distance(name, $0) < distance(name, $1) }
                let hint = suggestion.flatMap { distance(name, $0) <= 2 ? " Did you mean '\($0)'?" : nil } ?? ""
                diagnostics.append(source.diagnostic("Unknown key '\(name)'.\(hint)", at: key.mark, severity: .warning))
            }
            if let child = section.child(for: name) {
                diagnostics += Self.diagnostics(in: value, source: source, section: child, depth: depth + 1)
            }
        }
        return diagnostics
    }

    private static func distance(_ lhs: String, _ rhs: String) -> Int {
        let rhs = Array(rhs)
        var row = Array(0 ... rhs.count)
        for (index, character) in lhs.enumerated() {
            var next = [index + 1]
            for (column, other) in rhs.enumerated() {
                next.append(min(next[column] + 1, row[column + 1] + 1, row[column] + (character == other ? 0 : 1)))
            }
            row = next
        }
        return row[rhs.count]
    }
}
