import XCTest
@testable import Core

final class FeaturePolicyTests: XCTestCase {
    func testStudioWorkspaceIsGatedOff() {
        XCTAssertFalse(FeaturePolicy.studioWorkspaceEnabled)
        XCTAssertFalse(FeaturePolicy.isWorkspaceEnabled("studio"))
        XCTAssertEqual(FeaturePolicy.studioComingSoonMessage, "Studio is coming in a future version.")
    }

    func testOtherWorkspacesRemainEnabled() {
        for workspace in ["overview", "analytics", "assistant", "integrations"] {
            XCTAssertTrue(FeaturePolicy.isWorkspaceEnabled(workspace), workspace)
        }
    }
}
