import XCTest
@testable import AI
@testable import Core
@testable import Persistence
@testable import MCP
@testable import Instagram

final class AITests: XCTestCase {
    func testFixtureClaudeClientToolLoop() async throws {
        let db = try DatabaseManager.inMemory()
        let conversations = ConversationRepository(db: db)
        let audit = AuditLogRepository(db: db)
        let broker = DenyByDefaultApprovalBroker(allowAll: true)
        let gate = ToolPermissionGate(policy: ToolPermissionPolicy(allowedRoots: [FileManager.default.temporaryDirectory]), approvalBroker: broker)

        let toolResponse = ClaudeResponse(
            id: "1",
            model: "claude-sonnet-4-5",
            content: [
                .toolUse(id: "t1", name: "get_instagram_analytics", input: ["days": .number(30)])
            ],
            stopReason: "tool_use",
            usage: ClaudeUsage(inputTokens: 10, outputTokens: 5)
        )
        let finalResponse = ClaudeResponse(
            id: "2",
            model: "claude-sonnet-4-5",
            content: [.text("Missing data indicated by tool. No fabricated metrics.")],
            stopReason: "end_turn",
            usage: ClaudeUsage(inputTokens: 20, outputTokens: 10)
        )

        let client = SequencingClaudeClient(responses: [toolResponse, finalResponse])
        let orchestrator = AIOrchestrator(
            client: client,
            conversations: conversations,
            audit: audit,
            permissionGate: gate,
            configuration: AppConfiguration(applicationSupportDirectory: FileManager.default.temporaryDirectory),
            analyticsProvider: { days in
                GroundedAnalyticsPayload(
                    report: AnalyticsReport(
                        accountId: "acc",
                        periodStart: Date().addingTimeInterval(-Double(days) * 86400),
                        periodEnd: Date(),
                        observedMetrics: [],
                        missingMetrics: ["reach", "views"],
                        mediaRanking: []
                    ),
                    source: "fixture",
                    note: "fixture"
                )
            }
        )

        let result = try await orchestrator.handleUserMessage(conversationId: nil, text: "Analyze last 30 days")
        XCTAssertTrue(result.assistantText.contains("fabricated") || result.assistantText.contains("Missing"))
        XCTAssertFalse(result.toolAudit.isEmpty)
        XCTAssertTrue(result.missingData.contains("reach"))
    }

    func testUnapprovedToolDenied() async throws {
        let db = try DatabaseManager.inMemory()
        let broker = DenyByDefaultApprovalBroker(allowAll: false)
        var policy = ToolPermissionPolicy(allowedRoots: [FileManager.default.temporaryDirectory])
        policy.categoriesRequiringApproval = [.instagramAnalytics]
        let gate = ToolPermissionGate(policy: policy, approvalBroker: broker)
        let client = SequencingClaudeClient(responses: [
            ClaudeResponse(
                id: "1",
                model: "m",
                content: [.toolUse(id: "t1", name: "get_instagram_analytics", input: ["days": .number(7)])],
                stopReason: "tool_use"
            ),
            ClaudeResponse(id: "2", model: "m", content: [.text("Denied path handled.")], stopReason: "end_turn")
        ])
        let orchestrator = AIOrchestrator(
            client: client,
            conversations: ConversationRepository(db: db),
            audit: AuditLogRepository(db: db),
            permissionGate: gate,
            configuration: AppConfiguration(applicationSupportDirectory: FileManager.default.temporaryDirectory)
        )
        let result = try await orchestrator.handleUserMessage(conversationId: nil, text: "Analyze")
        XCTAssertEqual(result.toolAudit.first?.approved, false)
    }

    func testContextWindowTrim() {
        let manager = ContextWindowManager(maxMessages: 2)
        let trimmed = manager.trim([
            .user("1"), .user("2"), .user("3")
        ])
        XCTAssertEqual(trimmed.count, 2)
    }
}

final class SequencingClaudeClient: ClaudeAPIClient, @unchecked Sendable {
    private let responses: [ClaudeResponse]
    private let box = UnfairLockBox(0)

    init(responses: [ClaudeResponse]) {
        self.responses = responses
    }

    func createMessage(
        model: String,
        messages: [ClaudeMessage],
        tools: [ClaudeToolDefinition],
        maxTokens: Int,
        system: String?
    ) async throws -> ClaudeResponse {
        box.withLock { index in
            defer { index += 1 }
            guard index < responses.count else {
                return ClaudeResponse(id: "fallback", model: model, content: [.text("done")], stopReason: "end_turn")
            }
            return responses[index]
        }
    }

    func streamMessage(
        model: String,
        messages: [ClaudeMessage],
        tools: [ClaudeToolDefinition],
        maxTokens: Int,
        system: String?
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
