import XCTest
@testable import Core

final class CoreTests: XCTestCase {
    func testConfigurationValidation() throws {
        var config = AppConfiguration(applicationSupportDirectory: FileManager.default.temporaryDirectory)
        try config.validate()
        config.claudeMaxTokens = 0
        XCTAssertThrowsError(try config.validate())
    }

    func testModelCatalogAllowsConfiguredOverride() throws {
        let catalog = ModelCatalog.default
        XCTAssertEqual(try catalog.resolve(nil), "claude-sonnet-4-5")
        XCTAssertEqual(try catalog.resolve("custom-model-id"), "custom-model-id")
    }

    func testInMemoryKeychain() throws {
        let store = InMemoryKeychainStore()
        XCTAssertFalse(try store.hasSecret(account: "a"))
        try store.setSecret("secret", account: "a")
        XCTAssertEqual(try store.getSecret(account: "a"), "secret")
        try store.deleteSecret(account: "a")
        XCTAssertNil(try store.getSecret(account: "a"))
    }

    func testErrorClassifier() {
        if case .rateLimited = ErrorClassifier.classifyHTTP(status: 429, body: nil) {
            // ok
        } else {
            XCTFail("Expected rate limited")
        }
        if case .authentication = ErrorClassifier.classifyHTTP(status: 401, body: "nope") {
            // ok
        } else {
            XCTFail("Expected authentication")
        }
    }

    func testPathTraversalBlocked() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ias-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertThrowsError(try PathSafety.resolveContainedPath(path: "../etc/passwd", root: root))
        let ok = try PathSafety.resolveContainedPath(path: "media/a.mp4", root: root)
        XCTAssertTrue(ok.path.contains("media/a.mp4") || ok.path.hasSuffix("a.mp4"))
    }

    func testLogRedaction() {
        let redacted = StructuredLogger.redact("Authorization: Bearer sk-ant-secret-value")
        XCTAssertFalse(redacted.contains("sk-ant-secret-value"))
        XCTAssertTrue(redacted.contains("REDACTED"))
    }

    func testRetryDelayIncreases() {
        let policy = RetryPolicy(baseDelay: 1, maxDelay: 10, jitterFraction: 0)
        XCTAssertEqual(policy.delay(forAttempt: 1), 1)
        XCTAssertEqual(policy.delay(forAttempt: 2), 2)
        XCTAssertEqual(policy.delay(forAttempt: 3), 4)
    }

    func testServiceContainer() throws {
        let container = ServiceContainer()
        container.registerSingleton(42)
        XCTAssertEqual(try container.resolve(Int.self), 42)
        XCTAssertThrowsError(try container.resolve(String.self))
    }
}
