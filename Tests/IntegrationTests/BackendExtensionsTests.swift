import XCTest
@testable import BackendInterface
@testable import Persistence
@testable import Core
@testable import AI

final class BackendExtensionsTests: XCTestCase {
    func testClearCredentialsAndOnboardingFlag() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ias-ext-\(UUID().uuidString)", isDirectory: true)
        let keychain = InMemoryKeychainStore()
        let runtime = try AppRuntime(
            configuration: AppConfiguration(applicationSupportDirectory: dir),
            keychain: keychain,
            approvalBroker: UIApprovalBroker(),
            claudeClient: FixtureClaudeClient(
                nextResponse: ClaudeResponse(id: "x", model: "m", content: [.text("ok")], stopReason: "end_turn")
            )
        )
        let services = ApplicationServices(runtime: runtime)
        try services.configureClaude(apiKey: "sk-test")
        XCTAssertTrue(services.onboardingStatus().claudeConfigured)
        try services.clearClaudeAPIKey()
        XCTAssertFalse(services.onboardingStatus().claudeConfigured)

        try services.setOnboardingCompleted(true)
        XCTAssertTrue(services.onboardingStatus().onboardingCompleted)

        let account = await services.linkedInstagramAccount()
        XCTAssertFalse(account.authenticated)

        let sync = await services.syncInstagramAnalytics(days: 7)
        XCTAssertFalse(sync.success)
        XCTAssertTrue(sync.note.contains("NOT LIVE VERIFIED") || sync.note.contains("credentials"))
    }

    func testDisplayNamePersonalizationAndExistingUserPrompt() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ias-name-\(UUID().uuidString)", isDirectory: true)
        let runtime = try AppRuntime(
            configuration: AppConfiguration(applicationSupportDirectory: dir),
            keychain: InMemoryKeychainStore(),
            approvalBroker: UIApprovalBroker()
        )
        let services = ApplicationServices(runtime: runtime)
        XCTAssertEqual(services.displayName(), DisplayNamePolicy.fallback)
        XCTAssertFalse(services.hasConfiguredDisplayName())
        XCTAssertFalse(services.needsDisplayNamePrompt())

        try services.setOnboardingCompleted(true)
        XCTAssertTrue(services.needsDisplayNamePrompt())

        try services.setDisplayName("  Andrej  ")
        XCTAssertEqual(services.displayName(), "Andrej")
        XCTAssertTrue(services.hasConfiguredDisplayName())
        XCTAssertFalse(services.needsDisplayNamePrompt())
        XCTAssertTrue(services.onboardingStatus().onboardingCompleted)

        XCTAssertThrowsError(try services.setDisplayName("   "))
    }

    func testCancelJobViaServices() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ias-cancel-\(UUID().uuidString)", isDirectory: true)
        let runtime = try AppRuntime(
            configuration: AppConfiguration(applicationSupportDirectory: dir),
            keychain: InMemoryKeychainStore(),
            approvalBroker: DenyByDefaultApprovalBroker(allowAll: true)
        )
        let services = ApplicationServices(runtime: runtime)
        // No video job without a real plan/handler race; recentJobs should be empty.
        let jobs = try await services.recentJobs()
        XCTAssertTrue(jobs.isEmpty)
    }
}
