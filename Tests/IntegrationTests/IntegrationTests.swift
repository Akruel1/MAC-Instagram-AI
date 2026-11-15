import XCTest
@testable import BackendInterface
@testable import Persistence
@testable import MCP
@testable import Core
@testable import AI

final class IntegrationTests: XCTestCase {
    func testRuntimeBootWithoutGUI() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ias-int-\(UUID().uuidString)", isDirectory: true)
        let runtime = try AppRuntime(
            configuration: AppConfiguration(applicationSupportDirectory: dir),
            keychain: InMemoryKeychainStore(),
            approvalBroker: DenyByDefaultApprovalBroker(allowAll: true),
            claudeClient: FixtureClaudeClient(
                nextResponse: ClaudeResponse(id: "x", model: "m", content: [.text("hello")], stopReason: "end_turn")
            )
        )
        let services = ApplicationServices(runtime: runtime)
        let status = services.onboardingStatus()
        XCTAssertFalse(status.claudeConfigured)
        let diagnostics = services.diagnostics()
        XCTAssertTrue(diagnostics.databasePath.contains("ias-int-"))
        XCTAssertFalse(services.mcpReviewedIntegrations().isEmpty)
    }

    func testChatThroughServicesWithFixtureClient() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ias-chat-\(UUID().uuidString)", isDirectory: true)
        let client = FixtureClaudeClient(
            nextResponse: ClaudeResponse(id: "x", model: "m", content: [.text("Grounded reply")], stopReason: "end_turn")
        )
        let runtime = try AppRuntime(
            configuration: AppConfiguration(applicationSupportDirectory: dir),
            keychain: InMemoryKeychainStore(),
            approvalBroker: DenyByDefaultApprovalBroker(allowAll: true),
            claudeClient: client
        )
        try runtime.setClaudeAPIKey("test-key")
        let services = ApplicationServices(runtime: runtime)
        let result = try await services.sendChat(conversationId: nil, text: "Hi")
        XCTAssertEqual(result.assistantText, "Grounded reply")
        XCTAssertEqual(try services.listConversations().count, 1)
    }

    func testMCPStdioFixtureServer() async throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/mcp/echo_server.js")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path), "Missing fixture at \(script.path)")

        let node: String
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/node") {
            node = "/usr/local/bin/node"
        } else if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/node") {
            node = "/opt/homebrew/bin/node"
        } else {
            throw XCTSkip("Node.js not available for MCP stdio integration test")
        }

        let client = MCPStdioClient(command: node, arguments: [script.path], timeout: 10)
        try await client.start()
        let tools = try await client.listTools()
        XCTAssertTrue(tools.contains(where: { $0.name == "echo" }))
        let result = try await client.callTool(name: "echo", arguments: ["message": .string("ping")])
        XCTAssertNotNil(result)
        await client.stop()
    }

    func testSQLiteMigrationFreshDatabase() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mig-\(UUID().uuidString).sqlite")
        let db = try DatabaseManager(databaseURL: url)
        let conversations = ConversationRepository(db: db)
        try conversations.create(ConversationRecord(title: "m", model: "m"))
        XCTAssertEqual(try conversations.listConversations().count, 1)
    }
}
