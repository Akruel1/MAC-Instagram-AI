import Foundation
import GRDB
import Core

public final class DatabaseManager: @unchecked Sendable {
    public let dbQueue: DatabaseQueue
    public let databaseURL: URL

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        let dir = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: config)
        try migrator.migrate(dbQueue)
    }

    /// In-memory database for tests.
    public static func inMemory() throws -> DatabaseManager {
        let manager = DatabaseManager.__inMemoryUninitialized()
        try manager.migrator.migrate(manager.dbQueue)
        return manager
    }

    private init(dbQueue: DatabaseQueue, databaseURL: URL) {
        self.dbQueue = dbQueue
        self.databaseURL = databaseURL
    }

    private static func __inMemoryUninitialized() -> DatabaseManager {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        // swiftlint:disable:next force_try
        let queue = try! DatabaseQueue(configuration: config)
        return DatabaseManager(dbQueue: queue, databaseURL: URL(fileURLWithPath: ":memory:"))
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "conversations") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("model", .text).notNull()
            }
            try db.create(table: "messages") { t in
                t.column("id", .text).primaryKey()
                t.column("conversation_id", .text).notNull()
                    .references("conversations", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content_json", .text).notNull()
                t.column("token_input", .integer)
                t.column("token_output", .integer)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(table: "instagram_accounts") { t in
                t.column("id", .text).primaryKey()
                t.column("username", .text).notNull()
                t.column("account_type", .text)
                t.column("linked_at", .datetime).notNull()
            }
            try db.create(table: "instagram_media") { t in
                t.column("id", .text).primaryKey()
                t.column("account_id", .text).notNull()
                    .references("instagram_accounts", onDelete: .cascade)
                t.column("media_type", .text).notNull()
                t.column("caption", .text)
                t.column("permalink", .text)
                t.column("published_at", .datetime)
                t.column("fetched_at", .datetime).notNull()
            }
            try db.create(table: "instagram_metrics") { t in
                t.column("id", .text).primaryKey()
                t.column("account_id", .text)
                    .references("instagram_accounts", onDelete: .cascade)
                t.column("media_id", .text)
                    .references("instagram_media", onDelete: .cascade)
                t.column("metric_name", .text).notNull()
                t.column("metric_value", .double)
                t.column("period", .text).notNull()
                t.column("observed_at", .datetime).notNull()
                t.column("reporting_start", .datetime)
                t.column("reporting_end", .datetime)
                t.column("provenance", .text).notNull()
                t.column("completeness", .text).notNull()
            }
            try db.create(table: "jobs") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("state", .text).notNull()
                t.column("progress", .double).notNull().defaults(to: 0)
                t.column("payload_json", .text).notNull()
                t.column("result_json", .text)
                t.column("error_message", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("started_at", .datetime)
                t.column("finished_at", .datetime)
                t.column("attempt_count", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "mcp_servers") { t in
                t.column("id", .text).primaryKey()
                t.column("display_name", .text).notNull()
                t.column("command", .text).notNull()
                t.column("args_json", .text).notNull()
                t.column("enabled", .boolean).notNull()
                t.column("version", .text)
                t.column("installed_at", .datetime)
            }
            try db.create(table: "installation_state") { t in
                t.column("dependency_id", .text).primaryKey()
                t.column("status", .text).notNull()
                t.column("version", .text)
                t.column("path", .text)
                t.column("updated_at", .datetime).notNull()
                t.column("details_json", .text)
            }
            try db.create(table: "audit_logs") { t in
                t.column("id", .text).primaryKey()
                t.column("category", .text).notNull()
                t.column("action", .text).notNull()
                t.column("actor", .text).notNull()
                t.column("details_json", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2_app_preferences") { db in
            try db.create(table: "app_preferences") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
                t.column("updated_at", .datetime).notNull()
            }
        }
        return migrator
    }
}
