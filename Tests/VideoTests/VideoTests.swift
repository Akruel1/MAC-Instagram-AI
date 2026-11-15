import XCTest
@testable import Video
@testable import Core

final class VideoTests: XCTestCase {
    func testTypedOperationRejectsTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertThrowsError(
            try VideoOperation.trim(input: "../etc/passwd", output: "out.mp4", startSeconds: 0, durationSeconds: 1)
                .validated(allowedRoot: root)
        )
    }

    func testExportVerticalBuildsSafeArgs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let input = root.appendingPathComponent("in.mp4")
        let output = root.appendingPathComponent("out.mp4")
        try Data().write(to: input)
        let op = try VideoOperation.exportVertical(
            input: input.path,
            output: output.path,
            width: 1080,
            height: 1920,
            videoBitrate: "5M"
        ).validated(allowedRoot: root)
        let (_, args) = try op.ffmpegArguments()
        XCTAssertFalse(args.contains(where: { $0.contains(";") }))
        XCTAssertTrue(args.contains("1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2") || args.contains(where: { $0.contains("1080:1920") }))
    }

    func testRemotionOptionalUnavailable() async {
        let remotion = UnavailableRemotionRenderer()
        XCTAssertFalse(remotion.isAvailable)
        do {
            try await remotion.render(compositionID: "x", propsJSON: "{}", output: FileManager.default.temporaryDirectory)
            XCTFail("Should throw")
        } catch {
            // expected
        }
    }

    func testShellMetacharactersRejected() {
        XCTAssertThrowsError(try PathSafety.assertNoShellMetacharacters("a;rm -rf", label: "x"))
    }
}
