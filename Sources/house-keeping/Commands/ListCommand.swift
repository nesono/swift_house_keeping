import ArgumentParser
import Foundation
import HouseKeeping

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List configured rules",
    )

    @Option(name: [.long, .customShort("c")], help: "Path to config file")
    var config: String?

    @Flag(name: .long, help: "Show only enabled rules")
    var enabled = false

    @Flag(name: .long, help: "Show only disabled rules")
    var disabled = false

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .table

    enum OutputFormat: String, ExpressibleByArgument, Sendable {
        case table, json
    }

    func run() throws {
        let loader = ConfigLoader()
        let cfg = try loader.load(from: config)

        var rules = cfg.rules
        if enabled {
            rules = rules.filter(\.enabled)
        }
        if disabled {
            rules = rules.filter { !$0.enabled }
        }

        if rules.isEmpty {
            print("No rules found")
            return
        }

        switch format {
        case .table:
            printTable(rules)
        case .json:
            printJSON(rules)
        }
    }

    private func printTable(_ rules: [Rule]) {
        let nameWidth = max(rules.map(\.name.count).max() ?? 0, 4) + 2
        let header = "NAME".padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            + "STATUS".padding(toLength: 10, withPad: " ", startingAt: 0)
            + "TRIGGER".padding(toLength: 14, withPad: " ", startingAt: 0)
            + "PRIORITY".padding(toLength: 10, withPad: " ", startingAt: 0)
            + "PATHS"
        print(header)
        print(String(repeating: "-", count: header.count + 10))

        for rule in rules.sorted(by: { $0.priority < $1.priority }) {
            let status = rule.enabled ? "enabled" : "disabled"
            let trigger: String
            switch rule.trigger.type {
            case .schedule:
                trigger = "schedule/\(rule.trigger.interval ?? "?")"
            case .fileChange:
                let events = rule.trigger.events?.map(\.rawValue).joined(separator: ",") ?? ""
                trigger = "change/\(events)"
            }

            let line = rule.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
                + status.padding(toLength: 10, withPad: " ", startingAt: 0)
                + trigger.padding(toLength: 14, withPad: " ", startingAt: 0)
                + String(rule.priority).padding(toLength: 10, withPad: " ", startingAt: 0)
                + rule.watchPaths.joined(separator: ", ")
            print(line)
        }
    }

    private func printJSON(_ rules: [Rule]) {
        let items = rules.map { rule -> [String: Any] in
            var item: [String: Any] = [
                "name": rule.name,
                "enabled": rule.enabled,
                "priority": rule.priority,
                "trigger_type": rule.trigger.type.rawValue,
                "watch_paths": rule.watchPaths,
            ]
            if let desc = rule.description { item["description"] = desc }
            if let interval = rule.trigger.interval { item["interval"] = interval }
            if let events = rule.trigger.events { item["events"] = events.map(\.rawValue) }
            return item
        }
        if let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8)
        {
            print(str)
        }
    }
}
