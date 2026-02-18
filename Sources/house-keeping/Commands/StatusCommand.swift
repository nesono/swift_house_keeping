import ArgumentParser
import Foundation
import HouseKeeping

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show daemon status",
    )

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    @Option(name: [.long, .customShort("c")], help: "Path to config file")
    var config: String?

    func run() throws {
        let pid = DaemonRunner.readPid()
        let running = pid != nil

        if json {
            var info: [String: Any] = [
                "running": running,
            ]
            if let pid {
                info["pid"] = pid
            }

            // Try to get state store stats
            if let cfg = try? ConfigLoader().load(from: config) {
                let expanded = cfg.expandingPaths()
                if let store = try? StateStore(path: expanded.global.stateFile),
                   let stats = try? store.stats()
                {
                    info["total_processed"] = stats.totalProcessed
                    info["total_runs"] = stats.totalRuns
                    if let lastActivity = stats.lastActivity {
                        info["last_activity"] = ISO8601DateFormatter().string(from: lastActivity)
                    }
                }
            }

            if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8)
            {
                print(str)
            }
            return
        }

        if running {
            print("Daemon: running (PID \(pid!))")
        } else {
            print("Daemon: not running")
        }

        // Show state stats if available
        if let cfg = try? ConfigLoader().load(from: config) {
            let expanded = cfg.expandingPaths()
            if let store = try? StateStore(path: expanded.global.stateFile),
               let stats = try? store.stats()
            {
                print("Files processed: \(stats.totalProcessed)")
                print("Rule executions: \(stats.totalRuns)")
                if let lastActivity = stats.lastActivity {
                    let formatter = RelativeDateTimeFormatter()
                    formatter.unitsStyle = .full
                    print("Last activity: \(formatter.localizedString(for: lastActivity, relativeTo: Date()))")
                }
            }
        }
    }
}
