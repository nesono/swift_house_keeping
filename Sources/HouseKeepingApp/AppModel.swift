import AppKit
import HouseKeeping
import Observation

@MainActor
@Observable
final class AppModel {
    var document: ConfigDocument? {
        didSet {
            message = nil
            persistDraft()
        }
    }

    var message: String? {
        didSet { validationID = nil }
    }

    var validationID: UUID?
    var isError = false
    var loginEnabled = false
    var isBusy = false
    var running = false
    let configPath: String

    private let defaults = UserDefaults.standard
    private let draftKey: String
    private static let agentPath = Config.expandPath("~/Library/LaunchAgents/com.house-keeping.agent.plist")

    init() {
        // Respect a custom configuration already installed through the CLI.
        let path = Self.installedConfigPath() ?? Config.expandPath(ConfigLoader.defaultConfigPath)
        configPath = path
        draftKey = "configDraft:\(path)"
        do {
            let disk = try ConfigDocument(path: path)
            if let data = defaults.data(forKey: draftKey),
               let draft = try? JSONDecoder().decode(ConfigDocument.self, from: data),
               draft.url == disk.url
            {
                document = draft
                message = "Restored your unsaved draft. Save to apply it."
            } else {
                document = disk
            }
        } catch {
            show(error)
        }
        refreshStatus()
    }

    var isDirty: Bool {
        document?.isDirty ?? false
    }

    func refreshStatus() {
        loginEnabled = FileManager.default.fileExists(atPath: Self.agentPath)
        running = DaemonRunner.readPid() != nil
    }

    func validate() {
        guard document != nil else { return }
        defer { validationID = UUID() }
        do {
            guard let config = try document?.validate() else { return }
            isError = false
            message = "Configuration is valid. \(config.rules.count) rules, \(config.rules.filter(\.enabled).count) enabled."
        } catch {
            show(error)
        }
    }

    func save() {
        do {
            try document?.save()
            isError = false
            message = "Saved. The running daemon will reload your rules automatically."
        } catch {
            show(error)
        }
    }

    func reload() {
        do {
            document = try ConfigDocument(path: configPath)
            defaults.removeObject(forKey: draftKey)
            isError = false
            message = "Loaded configuration from disk."
        } catch {
            show(error)
        }
    }

    func setLoginEnabled(_ enabled: Bool) async {
        isBusy = true
        defer {
            isBusy = false
            refreshStatus()
        }
        do {
            if enabled {
                guard !isDirty else {
                    throw AppError.message("Save your rules before enabling Start at login.")
                }
                try document?.validate()
            }
            let binary = try Self.cliPath()
            let arguments = enabled ? ["install", "--config", configPath] : ["uninstall"]
            _ = try await Task.detached {
                try Self.runCLI(binary: binary, arguments: arguments)
            }.value
            isError = false
            message = enabled ? "Start at login enabled. The daemon is starting." : "Start at login disabled. The launch agent was stopped."
        } catch {
            show(error)
        }
    }

    func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: configPath)])
    }

    func openLogs() {
        do {
            let config = try ConfigLoader().load(from: configPath).expandingPaths()
            let url = URL(fileURLWithPath: config.global.logFile)
            if !NSWorkspace.shared.open(url) {
                throw AppError.message("The log file is not available yet: \(url.path)")
            }
        } catch {
            show(error)
        }
    }

    private func persistDraft() {
        if let document, document.isDirty, let data = try? JSONEncoder().encode(document) {
            defaults.set(data, forKey: draftKey)
        } else {
            defaults.removeObject(forKey: draftKey)
        }
    }

    private func show(_ error: Error) {
        isError = true
        message = (error as? ConfigError)?.description ?? error.localizedDescription
    }

    private static func installedConfigPath() -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: agentPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String],
              let index = arguments.firstIndex(of: "--config"), index + 1 < arguments.count
        else { return nil }
        return Config.expandPath(arguments[index + 1])
    }

    private static func cliPath() throws -> String {
        let candidates: [String?] = [
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("house-keeping").path,
            "/usr/local/bin/house_keeping",
        ]
        guard let path = candidates.compactMap(\.self).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AppError.message("The command-line tool could not be found. Reinstall House Keeping or build both executables.")
        }
        return path
    }

    private nonisolated static func runCLI(binary: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? "Command output was not valid UTF-8."
        guard process.terminationStatus == 0 else {
            throw AppError.message(output.isEmpty ? "Command failed (\(process.terminationStatus))." : output)
        }
        return output
    }
}

private enum AppError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): message
        }
    }
}
