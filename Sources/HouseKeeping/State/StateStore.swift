import Foundation
import GRDB

public struct ProcessedFile: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "processed_files"

    public var id: Int64?
    public var filePath: String
    public var ruleName: String
    public var processedAt: Date
    public var actionsTaken: String
    public var success: Bool

    public init(filePath: String, ruleName: String, processedAt: Date = Date(), actionsTaken: String, success: Bool) {
        self.filePath = filePath
        self.ruleName = ruleName
        self.processedAt = processedAt
        self.actionsTaken = actionsTaken
        self.success = success
    }

    public enum Columns {
        static let filePath = Column(CodingKeys.filePath)
        static let ruleName = Column(CodingKeys.ruleName)
        static let processedAt = Column(CodingKeys.processedAt)
    }
}

public struct RuleExecution: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "rule_executions"

    public var id: Int64?
    public var ruleName: String
    public var executedAt: Date
    public var filesMatched: Int
    public var filesProcessed: Int
    public var errors: Int

    public init(ruleName: String, executedAt: Date = Date(), filesMatched: Int, filesProcessed: Int, errors: Int) {
        self.ruleName = ruleName
        self.executedAt = executedAt
        self.filesMatched = filesMatched
        self.filesProcessed = filesProcessed
        self.errors = errors
    }
}

public final class StateStore: Sendable {
    private let dbPool: DatabasePool

    public init(path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        dbPool = try DatabasePool(path: path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: ProcessedFile.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("filePath", .text).notNull()
                t.column("ruleName", .text).notNull()
                t.column("processedAt", .datetime).notNull()
                t.column("actionsTaken", .text).notNull()
                t.column("success", .boolean).notNull()
            }

            try db.create(table: RuleExecution.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("ruleName", .text).notNull()
                t.column("executedAt", .datetime).notNull()
                t.column("filesMatched", .integer).notNull()
                t.column("filesProcessed", .integer).notNull()
                t.column("errors", .integer).notNull()
            }

            try db.create(
                index: "idx_processed_files_path_rule",
                on: ProcessedFile.databaseTableName,
                columns: ["filePath", "ruleName"]
            )
        }

        try migrator.migrate(dbPool)
    }

    public func recordProcessedFile(_ record: ProcessedFile) throws {
        try dbPool.write { db in
            try record.insert(db)
        }
    }

    public func recordRuleExecution(_ record: RuleExecution) throws {
        try dbPool.write { db in
            try record.insert(db)
        }
    }

    public func wasProcessed(filePath: String, ruleName: String, since: Date? = nil) throws -> Bool {
        try dbPool.read { db in
            var query = ProcessedFile
                .filter(ProcessedFile.Columns.filePath == filePath)
                .filter(ProcessedFile.Columns.ruleName == ruleName)
            if let since {
                query = query.filter(ProcessedFile.Columns.processedAt >= since)
            }
            return try query.fetchCount(db) > 0
        }
    }

    public func lastExecution(ruleName: String) throws -> RuleExecution? {
        try dbPool.read { db in
            try RuleExecution
                .filter(Column("ruleName") == ruleName)
                .order(Column("executedAt").desc)
                .fetchOne(db)
        }
    }

    public func recentProcessedFiles(limit: Int = 100) throws -> [ProcessedFile] {
        try dbPool.read { db in
            try ProcessedFile
                .order(ProcessedFile.Columns.processedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func stats() throws -> (totalProcessed: Int, totalRuns: Int, lastActivity: Date?) {
        try dbPool.read { db in
            let totalProcessed = try ProcessedFile.fetchCount(db)
            let totalRuns = try RuleExecution.fetchCount(db)
            let lastActivity = try ProcessedFile
                .select(max(ProcessedFile.Columns.processedAt))
                .fetchOne(db) as Date?
            return (totalProcessed, totalRuns, lastActivity)
        }
    }
}
