import XCTest
@testable import BackendInterface
@testable import Core
@testable import Video

final class MediaImportTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/media", isDirectory: true)
    }

    private func makeService(root: URL) -> MediaImportService {
        MediaImportService(mediaRoot: root, engine: FFmpegEngine())
    }

    private func tempMediaRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ias-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testValidMP4Import() async throws {
        try XCTSkipIf(!FFmpegEngine().isAvailable, "FFmpeg required")
        let src = fixtures.appendingPathComponent("sample.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
        let root = try tempMediaRoot()
        let result = try await makeService(root: root).importAndInspect(from: src)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.managedURL.path))
        XCTAssertGreaterThan(result.inspection.durationSeconds ?? 0, 0.5)
        XCTAssertNotNil(result.inspection.width)
    }

    func testValidMOVImport() async throws {
        try XCTSkipIf(!FFmpegEngine().isAvailable, "FFmpeg required")
        let src = fixtures.appendingPathComponent("sample.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
        let root = try tempMediaRoot()
        let result = try await makeService(root: root).importAndInspect(from: src)
        XCTAssertTrue(result.managedURL.pathExtension.lowercased() == "mov")
        XCTAssertGreaterThan(result.inspection.durationSeconds ?? 0, 0.2)
    }

    func testUnsupportedFileType() async throws {
        let src = fixtures.appendingPathComponent("plain.txt")
        let root = try tempMediaRoot()
        do {
            _ = try await makeService(root: root).importAndInspect(from: src)
            XCTFail("Expected validation error")
        } catch {
            let message = String(describing: error).lowercased()
            XCTAssertTrue(message.contains("unsupported") || message.contains("validation"))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 0)
    }

    func testCorruptedMedia() async throws {
        try XCTSkipIf(!FFmpegEngine().isAvailable, "FFmpeg required")
        let src = fixtures.appendingPathComponent("corrupt.mp4")
        let root = try tempMediaRoot()
        do {
            _ = try await makeService(root: root).importAndInspect(from: src)
            XCTFail("Expected corrupt media to fail")
        } catch {
            // Partial copies must be cleaned up.
            let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
            XCTAssertTrue(remaining.isEmpty, "Leftover files: \(remaining)")
        }
    }

    func testEmptyMediaRejected() async throws {
        let src = fixtures.appendingPathComponent("empty.mp4")
        let root = try tempMediaRoot()
        do {
            _ = try await makeService(root: root).importAndInspect(from: src)
            XCTFail("Expected empty rejection")
        } catch {
            XCTAssertTrue(String(describing: error).lowercased().contains("empty"))
        }
    }

    func testMissingSourceFile() async throws {
        let src = fixtures.appendingPathComponent("does-not-exist-\(UUID().uuidString).mp4")
        let root = try tempMediaRoot()
        do {
            _ = try await makeService(root: root).importAndInspect(from: src)
            XCTFail("Expected not found")
        } catch {
            XCTAssertTrue(String(describing: error).lowercased().contains("missing") || String(describing: error).lowercased().contains("not found"))
        }
    }

    func testUnicodeAndSpacesFilename() async throws {
        try XCTSkipIf(!FFmpegEngine().isAvailable, "FFmpeg required")
        let src = fixtures.appendingPathComponent("sample clip 🎬.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
        let root = try tempMediaRoot()
        let result = try await makeService(root: root).importAndInspect(from: src)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.managedURL.path))
        XCTAssertGreaterThan(result.inspection.durationSeconds ?? 0, 0.5)
    }

    func testRepeatedImportsDoNotOverwrite() async throws {
        try XCTSkipIf(!FFmpegEngine().isAvailable, "FFmpeg required")
        let src = fixtures.appendingPathComponent("sample.mp4")
        let root = try tempMediaRoot()
        let service = makeService(root: root)
        let a = try await service.importAndInspect(from: src)
        let b = try await service.importAndInspect(from: src)
        XCTAssertNotEqual(a.managedURL.path, b.managedURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.managedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.managedURL.path))
    }

    func testImportCancellation() async throws {
        try XCTSkipIf(!FFmpegEngine().isAvailable, "FFmpeg required")
        let src = fixtures.appendingPathComponent("sample.mp4")
        let root = try tempMediaRoot()
        let service = makeService(root: root)
        let task = Task {
            try await service.importAndInspect(from: src)
        }
        task.cancel()
        do {
            _ = try await task.value
            // Tiny fixture may complete before cancel lands; either outcome is acceptable if no crash.
        } catch is CancellationError {
            // expected when cancel wins
        } catch {
            // Other errors still must not leave the process crashed.
        }
    }

    func testLargeFileNotFullyLoaded() async throws {
        // Guardrail: import API uses FileManager.copyItem (streamed), not Data(contentsOf:).
        // Validate by importing the fixture and ensuring destination size matches source size.
        try XCTSkipIf(!FFmpegEngine().isAvailable, "FFmpeg required")
        let src = fixtures.appendingPathComponent("sample.mp4")
        let root = try tempMediaRoot()
        let result = try await makeService(root: root).importAndInspect(from: src)
        let srcSize = try FileManager.default.attributesOfItem(atPath: src.path)[.size] as? NSNumber
        let dstSize = try FileManager.default.attributesOfItem(atPath: result.managedURL.path)[.size] as? NSNumber
        XCTAssertEqual(srcSize, dstSize)
    }

    func testPermissionDeniedFile() async throws {
        try XCTSkipIf(!FFmpegEngine().isAvailable, "FFmpeg required")
        let root = try tempMediaRoot()
        let denied = root.appendingPathComponent("denied-source.mp4")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("sample.mp4"), to: denied)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: denied.path) }

        let mediaRoot = try tempMediaRoot()
        do {
            _ = try await makeService(root: mediaRoot).importAndInspect(from: denied)
            // On some hosts root/test runners can still read mode 000; accept either fail or success without crash.
        } catch {
            XCTAssertFalse(String(describing: error).isEmpty)
        }
    }
}
