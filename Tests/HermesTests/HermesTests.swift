import XCTest
@testable import Hermes
@testable import Dependencies
@testable import Core

final class HermesTests: XCTestCase {
    func testHermesOptionalWhenMissing() {
        let deps = DependencyManager(
            processRunner: FakeRunner(whichMap: [:]),
            approvalBroker: DenyByDefaultApprovalBroker(allowAll: true)
        )
        let hermes = HermesManager(
            dependencyManager: deps,
            keychain: InMemoryKeychainStore(),
            approvalBroker: DenyByDefaultApprovalBroker(allowAll: true),
            processRunner: FakeRunner(whichMap: [:])
        )
        let status = hermes.status()
        XCTAssertFalse(status.installed)
        XCTAssertTrue(status.notes.contains(where: { $0.lowercased().contains("optional") }))
    }

    func testInstallationPlanIsManualNotCurlPipe() {
        let deps = DependencyManager(
            processRunner: FakeRunner(whichMap: [:]),
            approvalBroker: DenyByDefaultApprovalBroker(allowAll: true)
        )
        let hermes = HermesManager(
            dependencyManager: deps,
            keychain: InMemoryKeychainStore(),
            approvalBroker: DenyByDefaultApprovalBroker(allowAll: true)
        )
        let plan = hermes.installationPlan()
        XCTAssertEqual(plan.steps.first?.packageManager, "manual")
        XCTAssertFalse(plan.steps.contains(where: { $0.command.contains("curl") }))
    }

    func testToolBridgeDisabledByDefault() async {
        let bridge = DisabledHermesToolBridge()
        XCTAssertTrue(bridge.exportedToolNames().isEmpty)
        do {
            _ = try await bridge.invokeApprovedTool(name: "x", payloadJSON: "{}", authToken: "t")
            XCTFail("Expected error")
        } catch {
            // expected
        }
    }
}

struct FakeRunner: ProcessRunnerLike {
    var whichMap: [String: String]
    func which(_ name: String) -> String? { whichMap[name] }
    func version(path: String) -> String? { "0.0.0" }
    func run(executable: String, arguments: [String]) async throws -> Int32 { 1 }
}
