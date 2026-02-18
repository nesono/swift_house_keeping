import ArgumentParser
import Foundation
import HouseKeeping

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install launchd agent for automatic startup"
    )

    @Option(name: [.long, .customShort("c")], help: "Path to config file")
    var config: String?

    func run() throws {
        let plistPath = Config.expandPath("~/Library/LaunchAgents/com.house-keeping.agent.plist")
        let executablePath = ProcessInfo.processInfo.arguments[0]
        let configPath = Config.expandPath(config ?? ConfigLoader.defaultConfigPath)

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

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: plistPath))

        print("LaunchAgent plist written to: \(plistPath)")

        // Load the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistPath]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("LaunchAgent loaded successfully. Daemon will start automatically on login.")
        } else {
            print("Warning: Failed to load LaunchAgent (exit code \(process.terminationStatus))")
            print("You can manually load it with: launchctl load \(plistPath)")
        }
    }
}

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove launchd agent"
    )

    @Flag(name: .long, help: "Also remove config, state, and log files")
    var purge = false

    func run() throws {
        let plistPath = Config.expandPath("~/Library/LaunchAgents/com.house-keeping.agent.plist")

        if FileManager.default.fileExists(atPath: plistPath) {
            // Unload the agent
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", plistPath]
            try process.run()
            process.waitUntilExit()

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
