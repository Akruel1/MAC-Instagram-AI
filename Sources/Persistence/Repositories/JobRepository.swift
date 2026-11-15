import Foundation
import GRDB
import Core

public enum JobState: String, Sendable, Codable, Equatable {
    case pending = "PENDING"
    case validating = "VALIDATING"
    case queued = "QUEUED"
    case running = "RUNNING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }
}

public struct JobRecord: Sendable, Equatable, Codable {
    public var id: String
    public var kind: String
    public var state: JobState
    public var progress: Double
    public var payloadJSON: String
    public var resultJSON: String?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var attemptCount: Int

    public init(
        id: String = UUID().uuidString,
        kind: String,
        state: JobState = .pending,
        progress: Double = 0,
        payloadJSON: String,
        resultJSON: String? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        attemptCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.state = state
        self.progress = progress
        self.payloadJSON = payloadJSON
        self.resultJSON = resultJSON
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.attemptCount = attemptCount
    }
}

public struct JobRepository: Sendable {
    private let dbQueue: DatabaseQueue

    public init(db: DatabaseManager) {
        self.dbQueue = db.dbQueue
    }

    public func insert(_ job: JobRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO jobs (id, kind, state, progress, payload_json, result_json, error_message,
                  created_at, updated_at, started_at, finished_at, attempt_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    job.id, job.kind, job.state.rawValue, job.progress, job.payloadJSON,
                    job.resultJSON, job.errorMessage, job.createdAt, job.updatedAt,
                    job.startedAt, job.finishedAt, job.attemptCount
                ]
            )
        }
    }

    public func update(_ job: JobRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE jobs SET state = ?, progress = ?, result_json = ?, error_message = ?,
                  updated_at = ?, started_at = ?, finished_at = ?, attempt_count = ?
                WHERE id = ?
                """,
                arguments: [
                    job.state.rawValue, job.progress, job.resultJSON, job.errorMessage,
                    job.updatedAt, job.startedAt, job.finishedAt, job.attemptCount, job.id
                ]
            )
        }
    }

    public func get(id: String) throws -> JobRecord? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM jobs WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return map(row)
        }
    }

    public func incomplete() throws -> [JobRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM jobs WHERE state NOT IN ('COMPLETED', 'FAILED', 'CANCELLED')
                ORDER BY created_at ASC
                """
            )
            return rows.map(map)
        }
    }

    public func recent(limit: Int = 20) throws -> [JobRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM jobs ORDER BY updated_at DESC LIMIT ?",
                arguments: [limit]
            )
            return rows.map(map)
        }
    }

    private func map(_ row: Row) -> JobRecord {
        JobRecord(
            id: row["id"],
            kind: row["kind"],
            state: JobState(rawValue: row["state"]) ?? .failed,
            progress: row["progress"],
            payloadJSON: row["payload_json"],
            resultJSON: row["result_json"],
            errorMessage: row["error_message"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"],
            startedAt: row["started_at"],
            finishedAt: row["finished_at"],
            attemptCount: row["attempt_count"]
        )
    }
}
