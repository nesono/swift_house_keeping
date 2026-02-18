import ArgumentParser
import Foundation
import HouseKeeping

struct DryRunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dry-run",
        abstract: "Show what would happen without making changes",
    )

    @Argument(help: "Rule name (optional, runs all enabled rules if omitted)")
    var rule: String?

    @Option(name: [.long, .customShort("c")], help: "Path to config file")
    var config: String?

    func run() throws {
        let loader = ConfigLoader()
        let cfg = try loader.load(from: config)

        let rulesToRun: [Rule]
        if let ruleName = rule {
            guard let matched = cfg.rules.first(where: { $0.name == ruleName }) else {
                print("Error: Rule '\(ruleName)' not found")
                throw ExitCode.failure
            }
            rulesToRun = [matched]
        } else {
            rulesToRun = cfg.rules.filter(\.enabled)
        }

        if rulesToRun.isEmpty {
            print("No rules to run")
            return
        }

        let engine = RuleEngine()
        let executor = ActionExecutor(dryRun: true)

        for ruleToRun in rulesToRun {
            print("Rule: \(ruleToRun.name)")
            if let desc = ruleToRun.description {
                print("  \(desc)")
            }
            print("  Trigger: \(ruleToRun.trigger.type.rawValue)", terminator: "")
            if let interval = ruleToRun.trigger.interval {
                print(" (every \(interval))", terminator: "")
            }
            print("")

            do {
                let matches = try engine.findMatches(rule: ruleToRun, config: cfg)
                if matches.isEmpty {
                    print("  No matching files\n")
                    continue
                }

                print("  \(matches.count) matching file(s):")
                for match in matches {
                    print("    \(match.file.name) (\(match.file.sizeHuman), \(String(format: "%.1f", match.file.ageDays))d old)")
                    let results = executor.execute(actions: match.rule.actions, on: match.file, ruleName: match.rule.name)
                    for result in results {
                        print("      -> \(result.message)")
                    }
                }
            } catch {
                print("  Error: \(error)")
            }
            print("")
        }
    }
}
