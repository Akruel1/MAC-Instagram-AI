import Foundation
import GRDB
import Core

public struct MCPServerRecord: Sendable, Equatable, Codable {
    public var id: String
    public var displayName: String
    public var command: String
    public var args: [String]
    public var enabled: Bool
    public var version: String?
    public var installedAt: Date?

    public init(
        id: String,
        displayName: String,
        command: String,
        args: [String] = [],
        enabled: Bool = false,
        version: String? = nil,
        installedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.command = command
        self.args = args
        self.enabled = enabled
        self.version = version
        self.installedAt = installedAt
    }
}

public struct MCPRegistryRepository: Sendable {
    private let dbQueue: DatabaseQueue

    public init(db: DatabaseManager) {
        self.dbQueue = db.dbQueue
    }

    public func upsert(_ server: MCPServerRecord) throws {
        let argsJSON = try jsonEncode(server.args)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO mcp_servers (id, display_name, command, args_json, enabled, version, installed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  display_name = excluded.display_name,
                  command = excluded.command,
                  args_json = excluded.args_json,
                  enabled = excluded.enabled,
                  version = excluded.version,
                  installed_at = excluded.installed_at
                """,
                arguments: [
                    server.id, server.displayName, server.command, argsJSON,
                    server.enabled, server.version, server.installedAt
                ]
            )
        }
    }

    public func list() throws -> [MCPServerRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM mcp_servers ORDER BY id")
            return try rows.map { row in
                MCPServerRecord(
                    id: row["id"],
                    displayName: row["display_name"],
                    command: row["command"],
                    args: try jsonDecode(row["args_json"]),
                    enabled: row["enabled"],
                    version: row["version"],
                    installedAt: row["installed_at"]
                )
            }
        }
    }

    private func jsonEncode(_ value: [String]) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let s = String(data: data, encoding: .utf8) else {
            throw AppError.persistence("JSON encode failed")
        }
        return s
    }

    private func jsonDecode(_ string: String) throws -> [String] {
        guard let data = string.data(using: .utf8) else { return [] }
        return try JSONDecoder().decode([String].self, from: data)
    }
}

public struct InstallationStateRecord: Sendable, Equatable, Codable {
    public var dependencyId: String
    public var status: String
    public var version: String?
    public var path: String?
    public var updatedAt: Date
    public var detailsJSON: String?

    public init(
        dependencyId: String,
        status: String,
        version: String? = nil,
        path: String? = nil,
        updatedAt: Date = Date(),
        detailsJSON: String? = nil
    ) {
        self.dependencyId = dependencyId
        self.status = status
        self.version = version
        self.path = path
        self.updatedAt = updatedAt
        self.detailsJSON = detailsJSON
    }
}

public struct InstallationStateRepository: Sendable {
    private let dbQueue: DatabaseQueue

    public init(db: DatabaseManager) {
        self.dbQueue = db.dbQueue
    }

    public func upsert(_ record: InstallationStateRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO installation_state (dependency_id, status, version, path, updated_at, details_json)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(dependency_id) DO UPDATE SET
                  status = excluded.status,
                  version = excluded.version,
                  path = excluded.path,
                  updated_at = excluded.updated_at,
                  details_json = excluded.details_json
                """,
                arguments: [
                    record.dependencyId, record.status, record.version,
                    record.path, record.updatedAt, record.detailsJSON
                ]
            )
        }
    }

    public func get(_ dependencyId: String) throws -> InstallationStateRecord? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM installation_state WHERE dependency_id = ?",
                arguments: [dependencyId]
            ) else { return nil }
            return InstallationStateRecord(
                dependencyId: row["dependency_id"],
                status: row["status"],
                version: row["version"],
                path: row["path"],
                updatedAt: row["updated_at"],
                detailsJSON: row["details_json"]
            )
        }
    }
}
