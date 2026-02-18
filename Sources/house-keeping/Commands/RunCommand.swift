import ArgumentParser
import Foundation
import HouseKeeping

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a specific rule"
    )

    @Argument(help: "Rule name to execute")
    var rule: String

    @Option(name: [.long, .customShort("c")], help: "Path to config file")
    var config: String?

    @Flag(name: .long, help: "Show what would happen without making changes")
    var dryRun = false

    @Flag(name: .long, help: "Run even if rule is disabled")
    var force = false

    @Option(name: .long, help: "Run against a specific file instead of watch paths")
    var file: String?

    func run() throws {
        let loader = ConfigLoader()
        let cfg = try loader.load(from: config)

        guard var matchedRule = cfg.rules.first(where: { $0.name == rule }) else {
            print("Error: Rule '\(rule)' not found")
            print("Available rules: \(cfg.rules.map(\.name).joined(separator: ", "))")
            throw ExitCode.failure
        }

        if !matchedRule.enabled && !force {
            print("Error: Rule '\(rule)' is disabled. Use --force to run anyway.")
            throw ExitCode.failure
        }

        if force {
            matchedRule.enabled = true
        }

        let engine = RuleEngine()
        let executor = ActionExecutor(dryRun: dryRun)

        if let filePath = file {
            // Run against a specific file
            let expandedPath = Config.expandPath(filePath)
            let url = URL(fileURLWithPath: expandedPath)

            guard FileManager.default.fileExists(atPath: expandedPath) else {
                print("Error: File not found: \(expandedPath)")
                throw ExitCode.failure
            }

            if let match = try engine.evaluateFile(at: url, rule: matchedRule) {
                print("File matches rule '\(matchedRule.name)'")
                let results = executor.execute(actions: match.rule.actions, on: match.file, ruleName: match.rule.name)
                printResults(results)
            } else {
                print("File does not match rule conditions")
            }
        } else {
            // Run against watch paths
            let matches = try engine.findMatches(rule: matchedRule, config: cfg)

            if matches.isEmpty {
                print("No files match rule '\(matchedRule.name)'")
                return
            }

            print("Found \(matches.count) matching file(s):")
            var totalResults: [ActionResult] = []

            // Set up state store for tracking
            let expanded = cfg.expandingPaths()
            let stateStore = try? StateStore(path: expanded.global.stateFile)

            for match in matches {
                print("\n  \(match.file.name)")
                let results = executor.execute(actions: match.rule.actions, on: match.file, ruleName: match.rule.name)
                totalResults.append(contentsOf: results)

                for result in results {
                    let icon = result.success ? "+" : "x"
                    print("    [\(icon)] \(result.message)")
                }

                if !dryRun {
                    let success = results.allSatisfy(\.success)
                    let actions = results.map(\.action).joined(separator: ", ")
                    try? stateStore?.recordProcessedFile(ProcessedFile(
                        filePath: match.file.path,
                        ruleName: matchedRule.name,
                        actionsTaken: actions,
                        success: success
                    ))
                }
            }

            if !dryRun {
                let successCount = totalResults.filter(\.success).count
                let errorCount = totalResults.count - successCount
                try? stateStore?.recordRuleExecution(RuleExecution(
                    ruleName: matchedRule.name,
                    filesMatched: matches.count,
                    filesProcessed: successCount,
                    errors: errorCount
                ))
            }

            let successCount = totalResults.filter(\.success).count
            print("\nDone: \(successCount)/\(totalResults.count) actions succeeded")
        }
    }

    private func printResults(_ results: [ActionResult]) {
        for result in results {
            let icon = result.success ? "+" : "x"
            print("  [\(icon)] \(result.message)")
        }
    }
}
