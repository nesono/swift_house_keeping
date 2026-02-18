import Foundation

public final class Logger: Sendable {
    public static let shared = Logger()

    private let _level: LogLevel
    private let _logFile: String?
    private let _lock = NSLock()

    public init(level: LogLevel = .info, logFile: String? = nil) {
        self._level = level
        self._logFile = logFile

        if let logFile {
            let dir = (logFile as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
    }

    private func shouldLog(_ level: LogLevel) -> Bool {
        let levels: [LogLevel] = [.debug, .info, .warning, .error]
        guard let currentIdx = levels.firstIndex(of: _level),
              let msgIdx = levels.firstIndex(of: level)
        else { return false }
        return msgIdx >= currentIdx
    }

    public func log(_ level: LogLevel, _ message: String) {
        guard shouldLog(level) else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue.uppercased())] \(message)\n"

        _lock.lock()
        defer { _lock.unlock() }

        FileHandle.standardError.write(Data(line.utf8))

        if let logFile = _logFile {
            if let handle = FileHandle(forWritingAtPath: logFile) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: logFile, contents: Data(line.utf8))
            }
        }
    }

    public func debug(_ message: String) { log(.debug, message) }
    public func info(_ message: String) { log(.info, message) }
    public func warning(_ message: String) { log(.warning, message) }
    public func error(_ message: String) { log(.error, message) }
}
