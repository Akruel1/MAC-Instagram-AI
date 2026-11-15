import XCTest
@testable import AppUI
@testable import BackendInterface
@testable import Core

@MainActor
final class StudioImportFlowTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/media", isDirectory: true)
    }

    func testAppModelImportValidMP4SetsInspection() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ias-studio-\(UUID().uuidString)", isDirectory: true)
        let runtime = try AppRuntime(
            configuration: AppConfiguration(applicationSupportDirectory: dir),
            keychain: InMemoryKeychainStore(),
            approvalBroker: UIApprovalBroker()
        )
        let model = AppModel(runtime: runtime)
        let src = fixtures.appendingPathComponent("sample.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))

        await model.loadImportedMedia(src)

        if model.features.ffmpegAvailable || FFmpegEngineProxy.isAvailable {
            XCTAssertNotNil(model.studioMediaURL, model.lastError ?? "no error")
            XCTAssertNotNil(model.studioInspection)
            XCTAssertGreaterThan(model.studioOutPoint, 0)
            XCTAssertNil(model.lastError)
        } else {
            XCTAssertNotNil(model.lastError)
            XCTAssertNil(model.studioMediaURL)
        }
    }

    func testAppModelImportUnsupportedSetsErrorWithoutPartialState() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ias-studio-bad-\(UUID().uuidString)", isDirectory: true)
        let runtime = try AppRuntime(
            configuration: AppConfiguration(applicationSupportDirectory: dir),
            keychain: InMemoryKeychainStore(),
            approvalBroker: UIApprovalBroker()
        )
        let model = AppModel(runtime: runtime)
        await model.loadImportedMedia(fixtures.appendingPathComponent("plain.txt"))
        XCTAssertNotNil(model.lastError)
        XCTAssertNil(model.studioMediaURL)
        XCTAssertNil(model.studioInspection)
    }
}

private enum FFmpegEngineProxy {
    static var isAvailable: Bool {
        // Lightweight PATH check mirroring Video.FFmpegEngine without importing Video in every assert.
        ["/opt/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
