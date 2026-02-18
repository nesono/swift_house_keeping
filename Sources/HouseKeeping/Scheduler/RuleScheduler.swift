import Foundation

public final class RuleScheduler: @unchecked Sendable {
    private var timers: [String: DispatchSourceTimer] = [:]
    private let queue = DispatchQueue(label: "com.house-keeping.scheduler", qos: .utility)
    private let handler: @Sendable (Rule) -> Void
    private let lock = NSLock()

    public init(handler: @escaping @Sendable (Rule) -> Void) {
        self.handler = handler
    }

    public func schedule(rules: [Rule]) {
        lock.lock()
        defer { lock.unlock() }

        // Stop existing timers
        for timer in timers.values {
            timer.cancel()
        }
        timers.removeAll()

        for rule in rules where rule.enabled && rule.trigger.type == .schedule {
            guard let interval = rule.trigger.intervalSeconds, interval > 0 else { continue }

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now() + interval,
                repeating: interval
            )

            let capturedRule = rule
            let capturedHandler = handler
            timer.setEventHandler {
                capturedHandler(capturedRule)
            }

            timer.resume()
            timers[rule.name] = timer
        }
    }

    public func runNow(rule: Rule) {
        queue.async { [handler] in
            handler(rule)
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        for timer in timers.values {
            timer.cancel()
        }
        timers.removeAll()
    }

    public var scheduledRuleNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(timers.keys)
    }

    deinit {
        stop()
    }
}
