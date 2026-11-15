import Foundation
import GRDB
import Core

public struct ConversationRecord: Sendable, Equatable, Codable {
    public var id: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var model: String

    public init(
        id: String = UUID().uuidString,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        model: String
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.model = model
    }
}

public struct MessageRecord: Sendable, Equatable, Codable {
    public var id: String
    public var conversationId: String
    public var role: String
    public var contentJSON: String
    public var tokenInput: Int?
    public var tokenOutput: Int?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        conversationId: String,
        role: String,
        contentJSON: String,
        tokenInput: Int? = nil,
        tokenOutput: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.contentJSON = contentJSON
        self.tokenInput = tokenInput
        self.tokenOutput = tokenOutput
        self.createdAt = createdAt
    }
}

public struct ConversationRepository: Sendable {
    private let dbQueue: DatabaseQueue

    public init(db: DatabaseManager) {
        self.dbQueue = db.dbQueue
    }

    public func create(_ conversation: ConversationRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO conversations (id, title, created_at, updated_at, model)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    conversation.id,
                    conversation.title,
                    conversation.createdAt,
                    conversation.updatedAt,
                    conversation.model
                ]
            )
        }
    }

    public func appendMessage(_ message: MessageRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO messages (id, conversation_id, role, content_json, token_input, token_output, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    message.id,
                    message.conversationId,
                    message.role,
                    message.contentJSON,
                    message.tokenInput,
                    message.tokenOutput,
                    message.createdAt
                ]
            )
            try db.execute(
                sql: "UPDATE conversations SET updated_at = ? WHERE id = ?",
                arguments: [Date(), message.conversationId]
            )
        }
    }

    public func messages(conversationId: String) throws -> [MessageRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM messages WHERE conversation_id = ? ORDER BY created_at ASC",
                arguments: [conversationId]
            )
            return rows.map { row in
                MessageRecord(
                    id: row["id"],
                    conversationId: row["conversation_id"],
                    role: row["role"],
                    contentJSON: row["content_json"],
                    tokenInput: row["token_input"],
                    tokenOutput: row["token_output"],
                    createdAt: row["created_at"]
                )
            }
        }
    }

    public func listConversations() throws -> [ConversationRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM conversations ORDER BY updated_at DESC")
            return rows.map { row in
                ConversationRecord(
                    id: row["id"],
                    title: row["title"],
                    createdAt: row["created_at"],
                    updatedAt: row["updated_at"],
                    model: row["model"]
                )
            }
        }
    }
}
