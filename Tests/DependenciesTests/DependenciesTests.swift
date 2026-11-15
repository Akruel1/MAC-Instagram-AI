import XCTest
@testable import Dependencies
@testable import Core

final class DependenciesTests: XCTestCase {
    func testDetectionAndPlan() {
        let runner = FakeProcessRunner(whichMap: ["node": "/usr/local/bin/node", "python3": "/usr/local/bin/python3"])
        let manager = DependencyManager(
            processRunner: runner,
            approvalBroker: DenyByDefaultApprovalBroker(allowAll: false),
            isExecutable: { _ in false }
        )
        let profile = manager.detectSystem()
        XCTAssertTrue(profile.dependencies.contains(where: { $0.id == "node" && $0.available }))
        XCTAssertFalse(profile.dependencies.contains(where: { $0.id == "ffmpeg" && $0.available }))
        let plan = manager.planInstallation(forMissingFrom: profile)
        XCTAssertFalse(plan.steps.isEmpty)
        XCTAssertTrue(plan.steps.contains(where: { $0.id.contains("ffmpeg") }))
    }

    func testInstallRequiresApproval() async {
        let runner = FakeProcessRunner(whichMap: [:])
        let manager = DependencyManager(processRunner: runner, approvalBroker: DenyByDefaultApprovalBroker(allowAll: false))
        let plan = InstallationPlan(steps: [
            InstallationStep(id: "install-ffmpeg", title: "ffmpeg", command: "brew", arguments: ["install", "ffmpeg"], packageManager: "homebrew", rationale: "test")
        ], summary: "test")
        do {
            try await manager.execute(plan: plan, approved: false)
            XCTFail("Expected denial")
        } catch {
            // expected
        }
    }

    func testUnsafeInstallerInputRejected() async {
        let runner = FakeProcessRunner(whichMap: [:])
        let manager = DependencyManager(processRunner: runner, approvalBroker: DenyByDefaultApprovalBroker(allowAll: true))
        let plan = InstallationPlan(steps: [
            InstallationStep(
                id: "evil",
                title: "evil",
                command: "brew",
                arguments: ["install", "ffmpeg; rm -rf /"],
                packageManager: "homebrew",
                rationale: "bad"
            )
        ], summary: "bad")
        do {
            try await manager.execute(plan: plan, approved: true)
            XCTFail("Expected unsafe rejection")
        } catch {
            // expected
        }
    }
}

struct FakeProcessRunner: ProcessRunnerLike {
    var whichMap: [String: String]
    func which(_ name: String) -> String? { whichMap[name] }
    func version(path: String) -> String? { "1.0.0" }
    func run(executable: String, arguments: [String]) async throws -> Int32 { 0 }
}
