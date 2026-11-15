import XCTest
@testable import AppUI
@testable import BackendInterface
@testable import Core
@testable import DesignSystem
@testable import Persistence

@MainActor
final class AppModelTests: XCTestCase {
    func testStudioNavigationIsBlockedFromSelect() async throws {
        let model = try makeModel()
        model.select(.overview)
        model.select(.studio)
        XCTAssertEqual(model.selectedWorkspace, .overview)
        XCTAssertEqual(model.lastError, FeaturePolicy.studioComingSoonMessage)
        XCTAssertFalse(AppModel.Workspace.studio.isEnabled)
    }

    func testEnabledWorkspacesRemainSelectable() async throws {
        let model = try makeModel()
        model.select(.analytics)
        XCTAssertEqual(model.selectedWorkspace, .analytics)
        model.select(.assistant)
        XCTAssertEqual(model.selectedWorkspace, .assistant)
        model.select(.integrations)
        XCTAssertEqual(model.selectedWorkspace, .integrations)
    }

    func testPrimaryActionDoesNotPreferGatedStudio() async throws {
        let model = try makeModel()
        model.features.ffmpegAvailable = true
        model.features.claudeConfigured = true
        model.features.instagramAuthenticated = true
        model.linkedAccount = LinkedInstagramAccountDTO(
            userID: "1",
            authenticated: true,
            tokenExpired: false,
            note: "Connected"
        )
        XCTAssertNotEqual(model.primaryAction, .openStudio)
        XCTAssertEqual(model.primaryAction, .refresh)
    }

    func testDisplayNameFallbackAndPersistence() async throws {
        let model = try makeModel()
        XCTAssertEqual(model.displayName, DisplayNamePolicy.fallback)
        model.displayNameDraft = "  Andrej  "
        model.saveDisplayNameFromDraft()
        XCTAssertEqual(model.displayName, "Andrej")
        await model.refreshSnapshot()
        XCTAssertEqual(model.displayName, "Andrej")
        XCTAssertFalse(model.showDisplayNamePrompt)
    }

    func testWhitespaceOnlyDisplayNameRejected() async throws {
        let model = try makeModel()
        model.displayNameDraft = "   "
        model.saveDisplayNameFromDraft()
        XCTAssertEqual(model.displayName, DisplayNamePolicy.fallback)
        XCTAssertNotNil(model.lastError)
    }

    func testExistingUserGetsOneTimeNamePromptWithoutResettingOnboarding() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ias-ui-migrate-\(UUID().uuidString)", isDirectory: true)
        let runtime = try AppRuntime(
            configuration: AppConfiguration(applicationSupportDirectory: dir),
            keychain: InMemoryKeychainStore(),
            approvalBroker: UIApprovalBroker()
        )
        try runtime.preferences.setBool(AppPreferenceKey.onboardingCompleted, true)
        let model = AppModel(runtime: runtime)
        XCTAssertFalse(model.showOnboarding)
        XCTAssertTrue(model.showDisplayNamePrompt)
        model.skipDisplayNamePrompt()
        XCTAssertFalse(model.showDisplayNamePrompt)
        XCTAssertEqual(model.displayName, DisplayNamePolicy.fallback)
        XCTAssertTrue(try runtime.preferences.getBool(AppPreferenceKey.onboardingCompleted))
    }

    func testPaletteResolvesDistinctLightAndDark() {
        let dark = StudioPalette(scheme: .dark)
        let light = StudioPalette(scheme: .light)
        XCTAssertNotEqual(dark.bgBase, light.bgBase)
        XCTAssertEqual(dark.accent, light.accent)
    }

    func testClaudeKeyAdvancesPrimaryAction() async throws {
        let model = try makeModel()
        model.claudeAPIKeyDraft = "sk-test"
        model.saveClaudeAPIKey()
        await model.refreshSnapshot()
        XCTAssertTrue(model.features.claudeConfigured)
        XCTAssertEqual(model.primaryAction, .connectInstagram)
    }

    private func makeModel() throws -> AppModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ias-ui-\(UUID().uuidString)", isDirectory: true)
        let runtime = try AppRuntime(
            configuration: AppConfiguration(applicationSupportDirectory: dir),
            keychain: InMemoryKeychainStore(),
            approvalBroker: UIApprovalBroker()
        )
        return AppModel(runtime: runtime)
    }
}
