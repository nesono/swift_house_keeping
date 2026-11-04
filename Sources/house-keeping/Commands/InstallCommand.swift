import ArgumentParser
import Darwin
import Foundation
import HouseKeeping

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install launchd agent for automatic startup",
    )

    @Option(name: [.long, .customShort("c")], help: "Path to config file")
    var config: String?

    func run() throws {
        let plistPath = Config.expandPath("~/Library/LaunchAgents/com.house-keeping.agent.plist")
        let executablePath = try LaunchControl.executablePath()
        let configPath = URL(fileURLWithPath: Config.expandPath(config ?? ConfigLoader.defaultConfigPath)).standardizedFileURL.path

        // Verify config exists and is valid
        let loader = ConfigLoader()
        let cfg = try loader.load(from: config)
        let errors = loader.validate(cfg)
        if !errors.isEmpty {
            print("Config has errors, fix them before installing:")
            for error in errors {
                print("  - \(error)")
            }
            throw ExitCode.failure
        }

        let plist: [String: Any] = [
            "Label": "com.house-keeping.agent",
            "ProgramArguments": [executablePath, "daemon", "--config", configPath],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": Config.expandPath("~/Library/Logs/house_keeping/stdout.log"),
            "StandardErrorPath": Config.expandPath("~/Library/Logs/house_keeping/stderr.log"),
            "ProcessType": "Background",
        ]

        let plistDir = (plistPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: plistDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            atPath: Config.expandPath("~/Library/Logs/house_keeping"),
            withIntermediateDirectories: true,
        )

        try LaunchControl.stopIfLoaded()

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: plistPath))

        print("LaunchAgent plist written to: \(plistPath)")

        // Load the agent
        if try LaunchControl.run(["bootstrap", LaunchControl.domain, plistPath]) == 0 {
            print("LaunchAgent loaded successfully. Daemon will start automatically on login.")
        } else {
            print("Failed to load LaunchAgent. Check System Settings > General > Login Items & Extensions.")
            print("You can manually load it with: launchctl bootstrap \(LaunchControl.domain) \(plistPath)")
            throw ExitCode.failure
        }
    }
}

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove launchd agent",
    )

    @Flag(name: .long, help: "Also remove config, state, and log files")
    var purge = false

    func run() throws {
        let plistPath = Config.expandPath("~/Library/LaunchAgents/com.house-keeping.agent.plist")

        if FileManager.default.fileExists(atPath: plistPath) {
            // Unload the agent
            try LaunchControl.stopIfLoaded()

            try FileManager.default.removeItem(atPath: plistPath)
            print("LaunchAgent removed: \(plistPath)")
        } else {
            print("LaunchAgent not installed")
        }

        if purge {
            let paths = [
                Config.expandPath("~/.config/house_keeping"),
                Config.expandPath("~/.local/share/house_keeping"),
                Config.expandPath("~/Library/Logs/house_keeping"),
            ]
            for path in paths {
                if FileManager.default.fileExists(atPath: path) {
                    try FileManager.default.removeItem(atPath: path)
                    print("Removed: \(path)")
                }
            }
        }
    }
}

private enum LaunchControl {
    static var domain: String {
        "gui/\(getuid())"
    }

    static var service: String {
        "\(domain)/com.house-keeping.agent"
    }

    static func executablePath() throws -> String {
        // Bundle.main may describe the GUI app when this CLI is its nested helper.
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            throw ValidationError("Could not resolve the command-line executable path.")
        }
        return buffer.withUnsafeBufferPointer {
            URL(fileURLWithPath: String(cString: $0.baseAddress!)).standardizedFileURL.path
        }
    }

    static func stopIfLoaded() throws {
        guard try run(["print", service], quiet: true) == 0 else { return }
        guard try run(["bootout", service]) == 0 else {
            print("Failed to stop the existing LaunchAgent.")
            throw ExitCode.failure
        }
    }

    static func run(_ arguments: [String], quiet: Bool = false) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        if quiet {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
