import ArgumentParser
import Foundation
import HouseKeeping

struct CheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Validate configuration file"
    )

    @Option(name: [.long, .customShort("c")], help: "Path to config file")
    var config: String?

    @Flag(name: .long, help: "Show verbose output")
    var verbose = false

    func run() throws {
        let loader = ConfigLoader()

        let cfg: Config
        do {
            cfg = try loader.load(from: config)
        } catch {
            print("Error: \(error)")
            throw ExitCode.failure
        }

        if verbose {
            print("Config version: \(cfg.version)")
            print("Log level: \(cfg.global.logLevel.rawValue)")
            print("Log file: \(cfg.global.logFile)")
            print("State file: \(cfg.global.stateFile)")
            print("Rules: \(cfg.rules.count)")
            for rule in cfg.rules {
                print("  - \(rule.name) [\(rule.enabled ? "enabled" : "disabled")] trigger=\(rule.trigger.type.rawValue)")
                if let desc = rule.description {
                    print("    \(desc)")
                }
            }
        }

        let errors = loader.validate(cfg)
        if errors.isEmpty {
            print("Config is valid. (\(cfg.rules.count) rules)")
        } else {
            print("Config validation errors:")
            for error in errors {
                print("  - \(error)")
            }
            throw ExitCode.failure
        }
    }
}
