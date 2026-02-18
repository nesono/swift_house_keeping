import Foundation

// MARK: - Top-Level Config

public struct Config: Codable, Sendable {
    public var version: Int
    public var global: GlobalConfig
    public var rules: [Rule]

    public init(version: Int = 1, global: GlobalConfig = GlobalConfig(), rules: [Rule] = []) {
        self.version = version
        self.global = global
        self.rules = rules
    }
}

// MARK: - Global Config

public struct GlobalConfig: Codable, Sendable {
    public var logLevel: LogLevel
    public var logFile: String
    public var stateFile: String

    public init(
        logLevel: LogLevel = .info,
        logFile: String = "~/Library/Logs/house_keeping/house_keeping.log",
        stateFile: String = "~/.local/share/house_keeping/state.db"
    ) {
        self.logLevel = logLevel
        self.logFile = logFile
        self.stateFile = stateFile
    }

    enum CodingKeys: String, CodingKey {
        case logLevel = "log_level"
        case logFile = "log_file"
        case stateFile = "state_file"
    }
}

public enum LogLevel: String, Codable, Sendable, CaseIterable {
    case debug, info, warning, error
}

// MARK: - Rule

public struct Rule: Codable, Sendable {
    public var name: String
    public var description: String?
    public var enabled: Bool
    public var priority: Int
    public var trigger: Trigger
    public var watchPaths: [String]
    public var recursive: Bool
    public var conditions: Condition
    public var actions: [Action]

    public init(
        name: String,
        description: String? = nil,
        enabled: Bool = true,
        priority: Int = 50,
        trigger: Trigger = .init(type: .schedule, interval: "1h", events: nil),
        watchPaths: [String] = [],
        recursive: Bool = false,
        conditions: Condition = .all([]),
        actions: [Action] = []
    ) {
        self.name = name
        self.description = description
        self.enabled = enabled
        self.priority = priority
        self.trigger = trigger
        self.watchPaths = watchPaths
        self.recursive = recursive
        self.conditions = conditions
        self.actions = actions
    }

    enum CodingKeys: String, CodingKey {
        case name, description, enabled, priority, trigger
        case watchPaths = "watch_paths"
        case recursive, conditions, actions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 50
        trigger = try container.decode(Trigger.self, forKey: .trigger)
        watchPaths = try container.decode([String].self, forKey: .watchPaths)
        recursive = try container.decodeIfPresent(Bool.self, forKey: .recursive) ?? false
        conditions = try container.decode(Condition.self, forKey: .conditions)
        actions = try container.decode([Action].self, forKey: .actions)
    }
}

// MARK: - Trigger

public struct Trigger: Codable, Sendable {
    public var type: TriggerType
    public var interval: String?
    public var events: [FileEventType]?

    public init(type: TriggerType, interval: String? = nil, events: [FileEventType]? = nil) {
        self.type = type
        self.interval = interval
        self.events = events
    }
}

public enum TriggerType: String, Codable, Sendable {
    case schedule
    case fileChange = "file_change"
}

public enum FileEventType: String, Codable, Sendable {
    case create, modify, delete, rename
}

// MARK: - Condition

public indirect enum Condition: Codable, Sendable {
    case all([Condition])
    case any([Condition])
    case none([Condition])
    case not(Condition)
    case ageDays(Comparison)
    case ageHours(Comparison)
    case ageModifiedDays(Comparison)
    case size(SizeComparison)
    case `extension`(StringListOrSingle)
    case nameMatches(String)
    case pathMatches(String)
    case hasTag(String)
    case tagCount(Comparison)
    case downloadedFrom(DownloadSource)
    case isQuarantined(Bool)
    case quarantineAgent(String)
    case contentMatches(ContentMatch)
    case isDirectory(Bool)
    case uti(String)

    enum CodingKeys: String, CodingKey {
        case all, any, none, not
        case ageDays = "age_days"
        case ageHours = "age_hours"
        case ageModifiedDays = "age_modified_days"
        case size, `extension`
        case nameMatches = "name_matches"
        case pathMatches = "path_matches"
        case hasTag = "has_tag"
        case tagCount = "tag_count"
        case downloadedFrom = "downloaded_from"
        case isQuarantined = "is_quarantined"
        case quarantineAgent = "quarantine_agent"
        case contentMatches = "content_matches"
        case isDirectory = "is_directory"
        case uti
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let children = try container.decodeIfPresent([Condition].self, forKey: .all) {
            self = .all(children)
        } else if let children = try container.decodeIfPresent([Condition].self, forKey: .any) {
            self = .any(children)
        } else if let children = try container.decodeIfPresent([Condition].self, forKey: .none) {
            self = .none(children)
        } else if let child = try container.decodeIfPresent(Condition.self, forKey: .not) {
            self = .not(child)
        } else if let comp = try container.decodeIfPresent(Comparison.self, forKey: .ageDays) {
            self = .ageDays(comp)
        } else if let comp = try container.decodeIfPresent(Comparison.self, forKey: .ageHours) {
            self = .ageHours(comp)
        } else if let comp = try container.decodeIfPresent(Comparison.self, forKey: .ageModifiedDays) {
            self = .ageModifiedDays(comp)
        } else if let comp = try container.decodeIfPresent(SizeComparison.self, forKey: .size) {
            self = .size(comp)
        } else if let val = try container.decodeIfPresent(StringListOrSingle.self, forKey: .extension) {
            self = .extension(val)
        } else if let val = try container.decodeIfPresent(String.self, forKey: .nameMatches) {
            self = .nameMatches(val)
        } else if let val = try container.decodeIfPresent(String.self, forKey: .pathMatches) {
            self = .pathMatches(val)
        } else if let val = try container.decodeIfPresent(String.self, forKey: .hasTag) {
            self = .hasTag(val)
        } else if let comp = try container.decodeIfPresent(Comparison.self, forKey: .tagCount) {
            self = .tagCount(comp)
        } else if let val = try container.decodeIfPresent(DownloadSource.self, forKey: .downloadedFrom) {
            self = .downloadedFrom(val)
        } else if let val = try container.decodeIfPresent(Bool.self, forKey: .isQuarantined) {
            self = .isQuarantined(val)
        } else if let val = try container.decodeIfPresent(String.self, forKey: .quarantineAgent) {
            self = .quarantineAgent(val)
        } else if let val = try container.decodeIfPresent(ContentMatch.self, forKey: .contentMatches) {
            self = .contentMatches(val)
        } else if let val = try container.decodeIfPresent(Bool.self, forKey: .isDirectory) {
            self = .isDirectory(val)
        } else if let val = try container.decodeIfPresent(String.self, forKey: .uti) {
            self = .uti(val)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "No recognized condition key found"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all(let children): try container.encode(children, forKey: .all)
        case .any(let children): try container.encode(children, forKey: .any)
        case .none(let children): try container.encode(children, forKey: .none)
        case .not(let child): try container.encode(child, forKey: .not)
        case .ageDays(let c): try container.encode(c, forKey: .ageDays)
        case .ageHours(let c): try container.encode(c, forKey: .ageHours)
        case .ageModifiedDays(let c): try container.encode(c, forKey: .ageModifiedDays)
        case .size(let c): try container.encode(c, forKey: .size)
        case .extension(let v): try container.encode(v, forKey: .extension)
        case .nameMatches(let v): try container.encode(v, forKey: .nameMatches)
        case .pathMatches(let v): try container.encode(v, forKey: .pathMatches)
        case .hasTag(let v): try container.encode(v, forKey: .hasTag)
        case .tagCount(let c): try container.encode(c, forKey: .tagCount)
        case .downloadedFrom(let v): try container.encode(v, forKey: .downloadedFrom)
        case .isQuarantined(let v): try container.encode(v, forKey: .isQuarantined)
        case .quarantineAgent(let v): try container.encode(v, forKey: .quarantineAgent)
        case .contentMatches(let v): try container.encode(v, forKey: .contentMatches)
        case .isDirectory(let v): try container.encode(v, forKey: .isDirectory)
        case .uti(let v): try container.encode(v, forKey: .uti)
        }
    }
}

// MARK: - Comparison Types

public struct Comparison: Codable, Sendable {
    public var gt: Double?
    public var lt: Double?
    public var gte: Double?
    public var lte: Double?
    public var eq: Double?

    public init(gt: Double? = nil, lt: Double? = nil, gte: Double? = nil, lte: Double? = nil, eq: Double? = nil) {
        self.gt = gt
        self.lt = lt
        self.gte = gte
        self.lte = lte
        self.eq = eq
    }

    public func evaluate(_ value: Double) -> Bool {
        if let gt, value <= gt { return false }
        if let lt, value >= lt { return false }
        if let gte, value < gte { return false }
        if let lte, value > lte { return false }
        if let eq, value != eq { return false }
        return true
    }
}

public struct SizeComparison: Codable, Sendable {
    public var gt: String?
    public var lt: String?
    public var gte: String?
    public var lte: String?
    public var between: [String]?

    public init(gt: String? = nil, lt: String? = nil, gte: String? = nil, lte: String? = nil, between: [String]? = nil) {
        self.gt = gt
        self.lt = lt
        self.gte = gte
        self.lte = lte
        self.between = between
    }

    public func evaluate(_ bytes: UInt64) -> Bool {
        if let gt, bytes <= SizeComparison.parseSize(gt) { return false }
        if let lt, bytes >= SizeComparison.parseSize(lt) { return false }
        if let gte, bytes < SizeComparison.parseSize(gte) { return false }
        if let lte, bytes > SizeComparison.parseSize(lte) { return false }
        if let between, between.count == 2 {
            let low = SizeComparison.parseSize(between[0])
            let high = SizeComparison.parseSize(between[1])
            if bytes < low || bytes > high { return false }
        }
        return true
    }

    public static func parseSize(_ str: String) -> UInt64 {
        let trimmed = str.trimmingCharacters(in: .whitespaces).uppercased()
        let multipliers: [(String, UInt64)] = [
            ("TB", 1_000_000_000_000),
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("KB", 1_000),
            ("B", 1),
        ]
        for (suffix, mult) in multipliers {
            if trimmed.hasSuffix(suffix) {
                let numStr = trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
                if let num = Double(numStr) {
                    return UInt64(num * Double(mult))
                }
            }
        }
        return UInt64(trimmed) ?? 0
    }
}

// MARK: - String List or Single

public enum StringListOrSingle: Codable, Sendable {
    case single(String)
    case list([String])

    public var values: [String] {
        switch self {
        case .single(let s): return [s]
        case .list(let arr): return arr
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let arr = try? container.decode([String].self) {
            self = .list(arr)
        } else if let s = try? container.decode(String.self) {
            self = .single(s)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected string or [string]")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let s): try container.encode(s)
        case .list(let arr): try container.encode(arr)
        }
    }
}

// MARK: - Download Source

public struct DownloadSource: Codable, Sendable {
    public var pattern: String?
    public var domain: String?

    public init(pattern: String? = nil, domain: String? = nil) {
        self.pattern = pattern
        self.domain = domain
    }
}

// MARK: - Content Match

public struct ContentMatch: Codable, Sendable {
    public var pattern: String
    public var maxSize: String?

    public init(pattern: String, maxSize: String? = nil) {
        self.pattern = pattern
        self.maxSize = maxSize
    }

    enum CodingKeys: String, CodingKey {
        case pattern
        case maxSize = "max_size"
    }

    public var maxSizeBytes: UInt64 {
        guard let maxSize else { return 5_000_000 } // 5MB default
        return SizeComparison.parseSize(maxSize)
    }
}

// MARK: - Action

public enum Action: Codable, Sendable {
    case setTag(String)
    case removeTag(String)
    case clearTags
    case setColorLabel(Int)
    case move(String)
    case copy(String)
    case trash(Bool)
    case delete(Bool)
    case rename(RenameAction)
    case runScript(String)
    case notify(NotifyAction)
    case log(String)
    case removeQuarantine(Bool)

    enum CodingKeys: String, CodingKey {
        case setTag = "set_tag"
        case removeTag = "remove_tag"
        case clearTags = "clear_tags"
        case setColorLabel = "set_color_label"
        case move, copy, trash, delete, rename
        case runScript = "run_script"
        case notify, log
        case removeQuarantine = "remove_quarantine"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let v = try container.decodeIfPresent(String.self, forKey: .setTag) {
            self = .setTag(v)
        } else if let v = try container.decodeIfPresent(String.self, forKey: .removeTag) {
            self = .removeTag(v)
        } else if let v = try container.decodeIfPresent(Bool.self, forKey: .clearTags) {
            if v { self = .clearTags } else { self = .clearTags }
        } else if let v = try container.decodeIfPresent(Int.self, forKey: .setColorLabel) {
            self = .setColorLabel(v)
        } else if let v = try container.decodeIfPresent(String.self, forKey: .move) {
            self = .move(v)
        } else if let v = try container.decodeIfPresent(String.self, forKey: .copy) {
            self = .copy(v)
        } else if let v = try container.decodeIfPresent(Bool.self, forKey: .trash) {
            self = .trash(v)
        } else if let v = try container.decodeIfPresent(Bool.self, forKey: .delete) {
            self = .delete(v)
        } else if let v = try container.decodeIfPresent(RenameAction.self, forKey: .rename) {
            self = .rename(v)
        } else if let v = try container.decodeIfPresent(String.self, forKey: .runScript) {
            self = .runScript(v)
        } else if let v = try container.decodeIfPresent(NotifyAction.self, forKey: .notify) {
            self = .notify(v)
        } else if let v = try container.decodeIfPresent(String.self, forKey: .log) {
            self = .log(v)
        } else if let v = try container.decodeIfPresent(Bool.self, forKey: .removeQuarantine) {
            self = .removeQuarantine(v)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No recognized action key found")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .setTag(let v): try container.encode(v, forKey: .setTag)
        case .removeTag(let v): try container.encode(v, forKey: .removeTag)
        case .clearTags: try container.encode(true, forKey: .clearTags)
        case .setColorLabel(let v): try container.encode(v, forKey: .setColorLabel)
        case .move(let v): try container.encode(v, forKey: .move)
        case .copy(let v): try container.encode(v, forKey: .copy)
        case .trash(let v): try container.encode(v, forKey: .trash)
        case .delete(let v): try container.encode(v, forKey: .delete)
        case .rename(let v): try container.encode(v, forKey: .rename)
        case .runScript(let v): try container.encode(v, forKey: .runScript)
        case .notify(let v): try container.encode(v, forKey: .notify)
        case .log(let v): try container.encode(v, forKey: .log)
        case .removeQuarantine(let v): try container.encode(v, forKey: .removeQuarantine)
        }
    }
}

public struct RenameAction: Codable, Sendable {
    public var pattern: String
    public var replacement: String

    public init(pattern: String, replacement: String) {
        self.pattern = pattern
        self.replacement = replacement
    }
}

public struct NotifyAction: Codable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

// MARK: - Interval Parsing

extension Trigger {
    public var intervalSeconds: TimeInterval? {
        guard let interval else { return nil }
        return Trigger.parseInterval(interval)
    }

    public static func parseInterval(_ str: String) -> TimeInterval? {
        let trimmed = str.trimmingCharacters(in: .whitespaces).lowercased()
        let suffixes: [(String, Double)] = [
            ("d", 86400), ("h", 3600), ("m", 60), ("s", 1),
        ]
        for (suffix, mult) in suffixes {
            if trimmed.hasSuffix(suffix) {
                let numStr = String(trimmed.dropLast(suffix.count))
                if let num = Double(numStr) {
                    return num * mult
                }
            }
        }
        return Double(trimmed)
    }
}

// MARK: - Path Expansion

extension Config {
    public func expandingPaths() -> Config {
        var config = self
        config.global.logFile = Config.expandPath(config.global.logFile)
        config.global.stateFile = Config.expandPath(config.global.stateFile)
        config.rules = config.rules.map { rule in
            var r = rule
            r.watchPaths = r.watchPaths.map { Config.expandPath($0) }
            return r
        }
        return config
    }

    public static func expandPath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return NSString(string: path).expandingTildeInPath
        }
        return path
    }
}
