import XCTest
@testable import Video
@testable import Core
@testable import Persistence
@testable import Jobs

/// Requires a real FFmpeg install (MacPorts/Homebrew). Skips when unavailable.
/// Also requires Xcode.app for XCTest (`swift test`). Prefer `swift run TestHarness` on CLT-only hosts.
final class FFmpegIntegrationTests: XCTestCase {
    func testLocatorFindsMacPortsOrPATH() throws {
        let locator = FFmpegLocator()
        guard let ffmpeg = locator.findFFmpeg(), let ffprobe = locator.findFFprobe() else {
            throw XCTSkip("ffmpeg/ffprobe not installed")
        }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: ffmpeg))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: ffprobe))
    }

    func testTrimConcatVerticalThumbnailAgainstRealFFmpeg() async throws {
        let engine = FFmpegEngine()
        guard engine.isAvailable else {
            throw XCTSkip("ffmpeg not installed")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xc-ffmpeg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ffmpeg = FFmpegLocator().findFFmpeg()!
        let src = root.appendingPathComponent("src.mp4").path
        let runner = FoundationProcessRunner()
        let gen = try await runner.run(
            executable: ffmpeg,
            arguments: [
                "-y", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=30",
                "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
                "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", src
            ],
            timeout: 60
        )
        XCTAssertEqual(gen.exitCode, 0)

        let trimmed = root.appendingPathComponent("t.mp4").path
        try await engine.execute(try VideoOperation.trim(input: src, output: trimmed, startSeconds: 0.2, durationSeconds: 0.8).validated(allowedRoot: root))
        let meta = try await engine.inspect(path: trimmed)
        XCTAssertNotNil(meta.durationSeconds)
        XCTAssertGreaterThan(meta.durationSeconds ?? 0, 0.4)

        let vertical = root.appendingPathComponent("v.mp4").path
        try await engine.execute(
            try VideoOperation.exportVertical(input: src, output: vertical, width: 720, height: 1280, videoBitrate: "500k")
                .validated(allowedRoot: root)
        )
        let vmeta = try await engine.inspect(path: vertical)
        XCTAssertEqual(vmeta.width, 720)
        XCTAssertEqual(vmeta.height, 1280)

        let srt = root.appendingPathComponent("c.srt")
        try """
        1
        00:00:00,000 --> 00:00:01,000
        Hello
        """.write(to: srt, atomically: true, encoding: .utf8)
        let subOut = root.appendingPathComponent("sub.mp4").path
        try await engine.execute(
            try VideoOperation.overlaySubtitles(input: src, srtPath: srt.path, output: subOut)
                .validated(allowedRoot: root)
        )
        let smeta = try await engine.inspect(path: subOut)
        XCTAssertEqual(smeta.width, 320)
        XCTAssertTrue(smeta.hasAudio)
    }

    func testLongRunningCancelTerminatesJob() async throws {
        let engine = FFmpegEngine()
        guard engine.isAvailable else { throw XCTSkip("ffmpeg not installed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xc-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ffmpeg = FFmpegLocator().findFFmpeg()!
        let longSrc = root.appendingPathComponent("long.mp4").path
        let out = root.appendingPathComponent("out.mp4").path
        let runner = FoundationProcessRunner()
        let gen = try await runner.run(
            executable: ffmpeg,
            arguments: [
                "-y", "-f", "lavfi", "-i", "testsrc=size=1280x720:rate=30",
                "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
                "-t", "15", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", longSrc
            ],
            timeout: 120
        )
        XCTAssertEqual(gen.exitCode, 0)

        let db = try DatabaseManager.inMemory()
        let coordinator = JobCoordinator(
            repository: JobRepository(db: db),
            audit: AuditLogRepository(db: db),
            logger: StructuredLogger(minimumLevel: .error)
        )
        await coordinator.register(
            VideoJobHandler(engine: engine, allowedRoot: root, approvalBroker: DenyByDefaultApprovalBroker(allowAll: true))
        )
        let plan = VideoEditPlan(
            operations: [.exportVertical(input: longSrc, output: out, width: 1080, height: 1920, videoBitrate: "2M")],
            requiresApproval: false
        )
        let payload = String(data: try JSONEncoder().encode(plan), encoding: .utf8) ?? "{}"
        let job = try await coordinator.submit(kind: "video.render", payloadJSON: payload)
        try await coordinator.enqueue(job.id)
        var running = false
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if try await coordinator.status(job.id).state == .running { running = true; break }
        }
        XCTAssertTrue(running)
        try await coordinator.cancel(job.id)
        try await Task.sleep(nanoseconds: 400_000_000)
        let status = try await coordinator.status(job.id)
        XCTAssertEqual(status.state, .cancelled)
    }
}
