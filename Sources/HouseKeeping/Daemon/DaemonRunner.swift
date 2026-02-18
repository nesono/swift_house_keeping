import Foundation

public final class DaemonRunner: @unchecked Sendable {
    private let config: Config
    private let stateStore: StateStore
    private let logger: Logger
    private let ruleEngine = RuleEngine()
    private var watchers: [FSEventWatcher] = []
    private var scheduler: RuleScheduler?
    private var configWatcher: FSEventWatcher?
    private let configPath: String?
    private var currentConfig: Config
    private let lock = NSLock()
    private let pidFilePath: String

    public init(config: Config, configPath: String? = nil) throws {
        self.config = config
        currentConfig = config
        self.configPath = configPath
        let expanded = config.expandingPaths()
        stateStore = try StateStore(path: expanded.global.stateFile)
        logger = Logger(level: config.global.logLevel, logFile: expanded.global.logFile)
        pidFilePath = NSTemporaryDirectory() + "house_keeping.pid"
    }

    public func run() async throws {
        writePidFile()
        defer { removePidFile() }

        logger.info("Daemon starting with \(currentConfig.rules.count) rules")

        setupScheduler()
        setupWatchers()
        setupConfigWatcher()
        setupSignalHandlers()

        logger.info("Daemon running. Press Ctrl+C to stop.")

        // Keep running
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
            // Block forever - signal handlers will terminate
            dispatchMain()
        }
    }

    private func setupScheduler() {
        let scheduler = RuleScheduler { [weak self] rule in
            self?.executeRule(rule)
        }

        let scheduledRules = currentConfig.rules.filter { $0.enabled && $0.trigger.type == .schedule }
        scheduler.schedule(rules: scheduledRules)
        self.scheduler = scheduler

        logger.info("Scheduled \(scheduledRules.count) rules")
        for rule in scheduledRules {
            logger.debug("  - \(rule.name): every \(rule.trigger.interval ?? "?")")
        }
    }

    private func setupWatchers() {
        let expanded = currentConfig.expandingPaths()
        let fileChangeRules = expanded.rules.filter { $0.enabled && $0.trigger.type == .fileChange }

        // Group by watch paths
        var pathToRules: [String: [Rule]] = [:]
        for rule in fileChangeRules {
            for path in rule.watchPaths {
                pathToRules[path, default: []].append(rule)
            }
        }

        for (path, rules) in pathToRules {
            let watcher = FSEventWatcher(paths: [path]) { [weak self] events in
                guard let self else { return }
                for event in events {
                    handleFileEvent(event, rules: rules)
                }
            }
            watcher.start()
            watchers.append(watcher)
            logger.info("Watching \(path) for \(rules.count) rules")
        }
    }

    private func setupConfigWatcher() {
        guard let configPath else { return }
        let expanded = Config.expandPath(configPath)
        let dir = (expanded as NSString).deletingLastPathComponent

        configWatcher = FSEventWatcher(paths: [dir]) { [weak self] events in
            guard let self else { return }
            for event in events {
                if event.path == expanded {
                    reloadConfig()
                }
            }
        }
        configWatcher?.start()
        logger.info("Watching config file for changes")
    }

    private func reloadConfig() {
        guard let configPath else { return }
        logger.info("Config file changed, reloading...")

        do {
            let loader = ConfigLoader()
            let newConfig = try loader.load(from: configPath)
            let errors = loader.validate(newConfig)
            if !errors.isEmpty {
                logger.error("Config validation failed after reload:\n\(errors.joined(separator: "\n"))")
                return
            }

            lock.lock()
            currentConfig = newConfig
            lock.unlock()

            // Restart watchers and scheduler
            for watcher in watchers {
                watcher.stop()
            }
            watchers.removeAll()
            scheduler?.stop()

            setupScheduler()
            setupWatchers()

            logger.info("Config reloaded successfully")
        } catch {
            logger.error("Failed to reload config: \(error)")
        }
    }

    private func handleFileEvent(_ event: FileEvent, rules: [Rule]) {
        let url = URL(fileURLWithPath: event.path)
        let matchingRules = rules.filter { rule in
            guard let events = rule.trigger.events else { return false }
            return events.contains(event.eventType)
        }

        guard !matchingRules.isEmpty else { return }

        for rule in matchingRules.sorted(by: { $0.priority < $1.priority }) {
            do {
                guard FileManager.default.fileExists(atPath: event.path) else { continue }

                if let match = try ruleEngine.evaluateFile(at: url, rule: rule) {
                    let executor = ActionExecutor(logger: logger)
                    let results = executor.execute(actions: match.rule.actions, on: match.file, ruleName: match.rule.name)

                    let success = results.allSatisfy(\.success)
                    let actions = results.map(\.action).joined(separator: ", ")

                    try? stateStore.recordProcessedFile(ProcessedFile(
                        filePath: event.path,
                        ruleName: rule.name,
                        actionsTaken: actions,
                        success: success,
                    ))

                    for result in results {
                        if result.success {
                            logger.info("[\(rule.name)] \(result.message)")
                        } else {
                            logger.error("[\(rule.name)] \(result.message)")
                        }
                    }
                }
            } catch {
                logger.error("[\(rule.name)] Error evaluating \(event.path): \(error)")
            }
        }
    }

    private func executeRule(_ rule: Rule) {
        logger.info("Executing scheduled rule: \(rule.name)")

        lock.lock()
        let config = currentConfig
        lock.unlock()

        do {
            let matches = try ruleEngine.findMatches(rule: rule, config: config)
            let executor = ActionExecutor(logger: logger)
            var processed = 0
            var errors = 0

            for match in matches {
                // Skip if already processed recently (within the interval)
                if let interval = rule.trigger.intervalSeconds,
                   let since = Calendar.current.date(byAdding: .second, value: -Int(interval), to: Date()),
                   (try? stateStore.wasProcessed(filePath: match.file.path, ruleName: rule.name, since: since)) == true
                {
                    continue
                }

                let results = executor.execute(actions: match.rule.actions, on: match.file, ruleName: match.rule.name)
                let success = results.allSatisfy(\.success)
                let actions = results.map(\.action).joined(separator: ", ")

                try? stateStore.recordProcessedFile(ProcessedFile(
                    filePath: match.file.path,
                    ruleName: rule.name,
                    actionsTaken: actions,
                    success: success,
                ))

                if success {
                    processed += 1
                } else {
                    errors += 1
                }

                for result in results {
                    if result.success {
                        logger.info("[\(rule.name)] \(result.message)")
                    } else {
                        logger.error("[\(rule.name)] \(result.message)")
                    }
                }
            }

            try? stateStore.recordRuleExecution(RuleExecution(
                ruleName: rule.name,
                filesMatched: matches.count,
                filesProcessed: processed,
                errors: errors,
            ))

            logger.info("[\(rule.name)] Completed: \(matches.count) matched, \(processed) processed, \(errors) errors")
        } catch {
            logger.error("[\(rule.name)] Execution failed: \(error)")
        }
    }

    private func setupSignalHandlers() {
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        signalSource.setEventHandler { [weak self] in
            self?.shutdown()
        }
        signalSource.resume()

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signal(SIGTERM, SIG_IGN)
        termSource.setEventHandler { [weak self] in
            self?.shutdown()
        }
        termSource.resume()

        // Hold references
        _signalSources = [signalSource, termSource]
    }

    private var _signalSources: [any DispatchSourceSignal] = []

    private func shutdown() {
        logger.info("Shutting down daemon...")
        for watcher in watchers {
            watcher.stop()
        }
        scheduler?.stop()
        configWatcher?.stop()
        removePidFile()
        exit(0)
    }

    private func writePidFile() {
        let pid = ProcessInfo.processInfo.processIdentifier
        try? "\(pid)".write(toFile: pidFilePath, atomically: true, encoding: .utf8)
    }

    private func removePidFile() {
        try? FileManager.default.removeItem(atPath: pidFilePath)
    }

    // MARK: - Status

    public static func readPid() -> Int32? {
        let pidFilePath = NSTemporaryDirectory() + "house_keeping.pid"
        guard let content = try? String(contentsOfFile: pidFilePath, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        // Check if process is actually running
        if kill(pid, 0) == 0 {
            return pid
        }
        return nil
    }
}
