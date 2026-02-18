import Foundation

public enum ActionError: Error, CustomStringConvertible {
    case moveFailed(String)
    case copyFailed(String)
    case trashFailed(String)
    case deleteFailed(String)
    case renameFailed(String)
    case scriptFailed(String)
    case tagFailed(String)

    public var description: String {
        switch self {
        case .moveFailed(let m): return "Move failed: \(m)"
        case .copyFailed(let m): return "Copy failed: \(m)"
        case .trashFailed(let m): return "Trash failed: \(m)"
        case .deleteFailed(let m): return "Delete failed: \(m)"
        case .renameFailed(let m): return "Rename failed: \(m)"
        case .scriptFailed(let m): return "Script failed: \(m)"
        case .tagFailed(let m): return "Tag failed: \(m)"
        }
    }
}

public struct ActionResult: Sendable {
    public let action: String
    public let success: Bool
    public let message: String
    public let newPath: String?

    public init(action: String, success: Bool, message: String, newPath: String? = nil) {
        self.action = action
        self.success = success
        self.message = message
        self.newPath = newPath
    }
}

public struct ActionExecutor: Sendable {
    public let dryRun: Bool
    public let logger: Logger

    public init(dryRun: Bool = false, logger: Logger = Logger.shared) {
        self.dryRun = dryRun
        self.logger = logger
    }

    public func execute(actions: [Action], on metadata: FileMetadata, ruleName: String) -> [ActionResult] {
        var results: [ActionResult] = []
        var currentURL = metadata.url

        for action in actions {
            let result = executeSingle(action, on: currentURL, metadata: metadata, ruleName: ruleName)
            results.append(result)

            if !result.success {
                break // Stop on first failure
            }

            // Track path changes from move/rename
            if let newPath = result.newPath {
                currentURL = URL(fileURLWithPath: newPath)
            }
        }

        return results
    }

    private func executeSingle(_ action: Action, on url: URL, metadata: FileMetadata, ruleName: String) -> ActionResult {
        switch action {
        case .setTag(let tag):
            return executeSetTag(tag, on: url, metadata: metadata, ruleName: ruleName)
        case .removeTag(let tag):
            return executeRemoveTag(tag, on: url, metadata: metadata, ruleName: ruleName)
        case .clearTags:
            return executeClearTags(on: url, metadata: metadata, ruleName: ruleName)
        case .setColorLabel(let label):
            return executeSetColorLabel(label, on: url, metadata: metadata, ruleName: ruleName)
        case .move(let dest):
            return executeMove(to: dest, on: url, metadata: metadata, ruleName: ruleName)
        case .copy(let dest):
            return executeCopy(to: dest, on: url, metadata: metadata, ruleName: ruleName)
        case .trash(let doTrash):
            if doTrash {
                return executeTrash(on: url, metadata: metadata, ruleName: ruleName)
            }
            return ActionResult(action: "trash", success: true, message: "Skipped (trash: false)")
        case .delete(let doDelete):
            if doDelete {
                return executeDelete(on: url, metadata: metadata, ruleName: ruleName)
            }
            return ActionResult(action: "delete", success: true, message: "Skipped (delete: false)")
        case .rename(let renameAction):
            return executeRename(renameAction, on: url, metadata: metadata, ruleName: ruleName)
        case .runScript(let script):
            return executeScript(script, on: url, metadata: metadata, ruleName: ruleName)
        case .notify(let notifyAction):
            return executeNotify(notifyAction, metadata: metadata, ruleName: ruleName)
        case .log(let message):
            return executeLog(message, metadata: metadata, ruleName: ruleName)
        case .removeQuarantine(let doRemove):
            if doRemove {
                return executeRemoveQuarantine(on: url, metadata: metadata, ruleName: ruleName)
            }
            return ActionResult(action: "remove_quarantine", success: true, message: "Skipped")
        }
    }

    // MARK: - Template Expansion

    func expandTemplate(_ template: String, metadata: FileMetadata, ruleName: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var result = template
        result = result.replacingOccurrences(of: "{path}", with: metadata.path)
        result = result.replacingOccurrences(of: "{name}", with: metadata.name)
        result = result.replacingOccurrences(of: "{ext}", with: metadata.ext)
        result = result.replacingOccurrences(of: "{size_human}", with: metadata.sizeHuman)
        result = result.replacingOccurrences(of: "{age_days}", with: String(format: "%.1f", metadata.ageDays))
        result = result.replacingOccurrences(of: "{tags}", with: metadata.tags.joined(separator: ", "))
        result = result.replacingOccurrences(of: "{download_url}", with: metadata.downloadURL ?? "")
        result = result.replacingOccurrences(of: "{rule_name}", with: ruleName)
        result = result.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: Date()))
        return result
    }
}

// MARK: - Tag Actions

extension ActionExecutor {
    private func executeSetTag(_ tag: String, on url: URL, metadata: FileMetadata, ruleName: String) -> ActionResult {
        let desc = "Set tag '\(tag)' on \(metadata.name)"
        if dryRun {
            return ActionResult(action: "set_tag", success: true, message: "[DRY RUN] \(desc)")
        }
        do {
            var currentTags = metadata.tags
            if !currentTags.contains(tag) {
                currentTags.append(tag)
            }
            try (url as NSURL).setResourceValue(currentTags, forKey: .tagNamesKey)
            return ActionResult(action: "set_tag", success: true, message: desc)
        } catch {
            return ActionResult(action: "set_tag", success: false, message: "Failed: \(error.localizedDescription)")
        }
    }

    private func executeRemoveTag(_ tag: String, on url: URL, metadata: FileMetadata, ruleName: String) -> ActionResult {
        let desc = "Remove tag '\(tag)' from \(metadata.name)"
        if dryRun {
            return ActionResult(action: "remove_tag", success: true, message: "[DRY RUN] \(desc)")
        }
        do {
            var currentTags = metadata.tags
            currentTags.removeAll { $0 == tag }
            try (url as NSURL).setResourceValue(currentTags, forKey: .tagNamesKey)
            return ActionResult(action: "remove_tag", success: true, message: desc)
        } catch {
            return ActionResult(action: "remove_tag", success: false, message: "Failed: \(error.localizedDescription)")
        }
    }

    private func executeClearTags(on url: URL, metadata: FileMetadata, ruleName: String) -> ActionResult {
        let desc = "Clear tags from \(metadata.name)"
        if dryRun {
            return ActionResult(action: "clear_tags", success: true, message: "[DRY RUN] \(desc)")
        }
        do {
            try (url as NSURL).setResourceValue([] as [String], forKey: .tagNamesKey)
            return ActionResult(action: "clear_tags", success: true, message: desc)
        } catch {
            return ActionResult(action: "clear_tags", success: false, message: "Failed: \(error.localizedDescription)")
        }
    }

    private func executeSetColorLabel(_ label: Int, on url: URL, metadata: FileMetadata, ruleName: String) -> ActionResult {
        let desc = "Set color label \(label) on \(metadata.name)"
        if dryRun {
            return ActionResult(action: "set_color_label", success: true, message: "[DRY RUN] \(desc)")
        }
        do {
            try (url as NSURL).setResourceValue(label, forKey: .labelNumberKey)
            return ActionResult(action: "set_color_label", success: true, message: desc)
        } catch {
            return ActionResult(action: "set_color_label", success: false, message: "Failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - File Actions

extension ActionExecutor {
    private func executeMove(to dest: String, on url: URL, metadata: FileMetadata, ruleName: String) -> ActionResult {
        let expandedDest = Config.expandPath(expandTemplate(dest, metadata: metadata, ruleName: ruleName))
        let destURL = URL(fileURLWithPath: expandedDest)
        let finalURL = destURL.appendingPathComponent(metadata.name)
        let desc = "Move \(metadata.name) → \(expandedDest)"

        if dryRun {
            return ActionResult(action: "move", success: true, message: "[DRY RUN] \(desc)", newPath: finalURL.path)
        }

        do {
            try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: finalURL)
            return ActionResult(action: "move", success: true, message: desc, newPath: finalURL.path)
        } catch {
            return ActionResult(action: "move", success: false, message: "Failed: \(error.localizedDescription)")
        }
    }

    private func executeCopy(to dest: String, on url: URL, metadata: FileMetadata, ruleName: String) -> ActionResult {
        let expandedDest = Config.expandPath(expandTemplate(dest, metadata: metadata, ruleName: ruleName))
        let destURL = URL(fileURLWithPath: expandedDest)
        let finalURL = destURL.appendingPathComponent(metadata.name)
        let desc = "Copy \(metadata.name) → \(expandedDest)"

        if dryRun {
            return ActionResult(action: "copy", success: true, message: "[DRY RUN] \(desc)")
        }

        do {
            try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: finalURL)
            return ActionResult(action: "copy", success: true, message: desc)
        } catch {
            return ActionResult(action: "copy", success: false, message: "Failed: \(error.localizedDescription)")
        }
    }

    private func executeTrash(on url: URL, metadata: FileMetadata, ruleName: String) -> ActionResult {
        let desc = "Trash \(metadata.name)"
        if dryRun {
            return ActionResult(action: "trash", success: true, message: "[DRY RUN] \(desc)")
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return ActionResult(action: "trash", success: true, message: desc)
        } catch {
            return ActionResult(action: "trash", success: false, message: "Failed: \(error.localizedDescription)")
        }
    }

    private func executeDelete(on url: URL, metadata: FileMetadata, ruleName: String) -> ActionResult {
        let desc = "Delete \(metadata.name)"
        if dryRun {
            return ActionResult(action: "delete", success: true, message: "[DRY RUN] \(desc)")
        }
        do {
            try FileManager.default.removeItem(at: url)
            return ActionResult(action: "delete", success: true, message: desc)
        } catch {
            return ActionResult(action: "delete", success: false, message: "Failed: \(error.localizedDescription)")
        }
    }

    private func executeRename(_ renameAction: RenameAction, on url: URL, metadata: FileMetadata, ruleName: String) -> ActionResult {
        guard let regex = try? NSRegularExpression(pattern: renameAction.pattern) else {
            return ActionResult(action: "rename", success: false, message: "Invalid regex pattern")
        }
        let range = NSRange(metadata.name.startIndex..., in: metadata.name)
        let newName = regex.stringByReplacingMatches(in: metadata.name, range: range, withTemplate: renameAction.replacement)
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        let desc = "Rename \(metadata.name) → \(newName)"

        if dryRun {
            return ActionResult(action: "rename", success: true, message: "[DRY RUN] \(desc)", newPath: newURL.path)
        }

        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            return ActionResult(action: "rename", success: true, message: desc, newPath: newURL.path)
        } catch {
            return ActionResult(action: "rename", success: false, message: "Failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - External Actions

extension ActionExecutor {
    private func executeScript(_ script: String, on url: URL, metadata: FileMetadata, ruleName: String) -> ActionResult {
        let expandedScript = expandTemplate(script, metadata: metadata, ruleName: ruleName)
        let desc = "Run script: \(expandedScript)"

        if dryRun {
            return ActionResult(action: "run_script", success: true, message: "[DRY RUN] \(desc)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", expandedScript]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "HK_FILE_PATH": metadata.path,
            "HK_FILE_NAME": metadata.name,
            "HK_RULE_NAME": ruleName,
        ]) { _, new in new }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if process.terminationStatus == 0 {
                return ActionResult(action: "run_script", success: true, message: "\(desc)\n\(output)")
            } else {
                return ActionResult(action: "run_script", success: false, message: "Script exited with \(process.terminationStatus): \(output)")
            }
        } catch {
            return ActionResult(action: "run_script", success: false, message: "Failed: \(error.localizedDescription)")
        }
    }

    private func executeNotify(_ notifyAction: NotifyAction, metadata: FileMetadata, ruleName: String) -> ActionResult {
        let title = expandTemplate(notifyAction.title, metadata: metadata, ruleName: ruleName)
        let body = expandTemplate(notifyAction.body, metadata: metadata, ruleName: ruleName)
        let desc = "Notify: \(title) - \(body)"

        if dryRun {
            return ActionResult(action: "notify", success: true, message: "[DRY RUN] \(desc)")
        }

        // Use osascript for notifications (simpler than UNUserNotificationCenter for CLI)
        let script = """
            display notification "\(body.replacingOccurrences(of: "\"", with: "\\\""))" \
            with title "\(title.replacingOccurrences(of: "\"", with: "\\\""))"
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()

        return ActionResult(action: "notify", success: true, message: desc)
    }

    private func executeLog(_ message: String, metadata: FileMetadata, ruleName: String) -> ActionResult {
        let expanded = expandTemplate(message, metadata: metadata, ruleName: ruleName)
        logger.info("[\(ruleName)] \(expanded)")
        return ActionResult(action: "log", success: true, message: expanded)
    }

    private func executeRemoveQuarantine(on url: URL, metadata: FileMetadata, ruleName: String) -> ActionResult {
        let desc = "Remove quarantine from \(metadata.name)"
        if dryRun {
            return ActionResult(action: "remove_quarantine", success: true, message: "[DRY RUN] \(desc)")
        }

        let result = removexattr(url.path, "com.apple.quarantine", 0)
        if result == 0 || errno == ENOATTR {
            return ActionResult(action: "remove_quarantine", success: true, message: desc)
        } else {
            return ActionResult(action: "remove_quarantine", success: false, message: "Failed to remove quarantine xattr")
        }
    }
}
