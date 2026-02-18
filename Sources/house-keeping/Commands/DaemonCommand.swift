import ArgumentParser
import Foundation
import HouseKeeping

struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Run the file management daemon"
    )

    @Option(name: [.long, .customShort("c")], help: "Path to config file")
    var config: String?

    @Flag(name: .long, help: "Run in foreground (don't daemonize)")
    var foreground = false

    func run() async throws {
        let loader = ConfigLoader()
        let cfg: Config
        do {
            cfg = try loader.load(from: config)
        } catch {
            print("Error: \(error)")
            throw ExitCode.failure
        }

        let errors = loader.validate(cfg)
        if !errors.isEmpty {
            print("Config validation errors:")
            for error in errors {
                print("  - \(error)")
            }
            throw ExitCode.failure
        }

        if DaemonRunner.readPid() != nil {
            print("Error: Daemon is already running")
            throw ExitCode.failure
        }

        let daemon = try DaemonRunner(config: cfg, configPath: config ?? ConfigLoader.defaultConfigPath)
        try await daemon.run()
    }
}
