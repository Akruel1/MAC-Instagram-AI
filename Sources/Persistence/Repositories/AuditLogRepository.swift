import Foundation
import GRDB
import Core

public struct AuditLogEntry: Sendable, Equatable, Codable {
    public var id: String
    public var category: String
    public var action: String
    public var actor: String
    public var details: [String: String]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        category: String,
        action: String,
        actor: String = "system",
        details: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.action = action
        self.actor = actor
        self.details = details
        self.createdAt = createdAt
    }
}

public struct AuditLogRepository: Sendable {
    private let dbQueue: DatabaseQueue

    public init(db: DatabaseManager) {
        self.dbQueue = db.dbQueue
    }

    public func append(_ entry: AuditLogEntry) throws {
        let detailsJSON = try jsonString(entry.details)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO audit_logs (id, category, action, actor, details_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [entry.id, entry.category, entry.action, entry.actor, detailsJSON, entry.createdAt]
            )
        }
    }

    public func recent(limit: Int = 100) throws -> [AuditLogEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT ?",
                arguments: [limit]
            )
            return try rows.map { row in
                AuditLogEntry(
                    id: row["id"],
                    category: row["category"],
                    action: row["action"],
                    actor: row["actor"],
                    details: try jsonObject(row["details_json"]),
                    createdAt: row["created_at"]
                )
            }
        }
    }
}

func jsonString(_ dict: [String: String]) throws -> String {
    let data = try JSONEncoder().encode(dict)
    guard let s = String(data: data, encoding: .utf8) else {
        throw AppError.persistence("Failed to encode JSON")
    }
    return s
}

func jsonObject(_ string: String) throws -> [String: String] {
    guard let data = string.data(using: .utf8) else { return [:] }
    return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
}
