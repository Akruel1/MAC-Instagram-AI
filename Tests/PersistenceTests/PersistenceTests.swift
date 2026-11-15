import XCTest
@testable import Persistence
@testable import Core

final class PersistenceTests: XCTestCase {
    func testMigrationsAndConversationRoundTrip() throws {
        let db = try DatabaseManager.inMemory()
        let conversations = ConversationRepository(db: db)
        let conversation = ConversationRecord(title: "Test", model: "claude-sonnet-4-5")
        try conversations.create(conversation)
        try conversations.appendMessage(
            MessageRecord(conversationId: conversation.id, role: "user", contentJSON: "[{\"type\":\"text\",\"text\":\"hi\"}]")
        )
        let messages = try conversations.messages(conversationId: conversation.id)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(try conversations.listConversations().count, 1)
    }

    func testJobStatePersistence() throws {
        let db = try DatabaseManager.inMemory()
        let jobs = JobRepository(db: db)
        var job = JobRecord(kind: "video.render", payloadJSON: "{}")
        try jobs.insert(job)
        job.state = .running
        job.progress = 0.5
        try jobs.update(job)
        let loaded = try jobs.get(id: job.id)
        XCTAssertEqual(loaded?.state, .running)
        XCTAssertEqual(loaded?.progress, 0.5)
    }

    func testForeignKeysEnabled() throws {
        let db = try DatabaseManager.inMemory()
        let conversations = ConversationRepository(db: db)
        XCTAssertThrowsError(
            try conversations.appendMessage(
                MessageRecord(conversationId: "missing", role: "user", contentJSON: "[]")
            )
        )
    }

    func testAuditLog() throws {
        let db = try DatabaseManager.inMemory()
        let audit = AuditLogRepository(db: db)
        try audit.append(AuditLogEntry(category: "test", action: "ping", details: ["a": "b"]))
        XCTAssertEqual(try audit.recent().count, 1)
    }
}
