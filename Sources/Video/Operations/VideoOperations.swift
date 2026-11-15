import Foundation
import Core

public struct MediaInspection: Sendable, Equatable, Codable {
    public var path: String
    public var durationSeconds: Double?
    public var width: Int?
    public var height: Int?
    public var aspectRatio: String?
    public var hasAudio: Bool
    public var format: String?

    public init(
        path: String,
        durationSeconds: Double? = nil,
        width: Int? = nil,
        height: Int? = nil,
        aspectRatio: String? = nil,
        hasAudio: Bool = false,
        format: String? = nil
    ) {
        self.path = path
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
        self.aspectRatio = aspectRatio
        self.hasAudio = hasAudio
        self.format = format
    }
}

public enum VideoOperation: Sendable, Equatable, Codable {
    case inspect(path: String)
    case trim(input: String, output: String, startSeconds: Double, durationSeconds: Double)
    case concatenate(inputs: [String], output: String)
    case extractAudio(input: String, output: String)
    case replaceAudio(video: String, audio: String, output: String)
    case overlaySubtitles(input: String, srtPath: String, output: String)
    case exportVertical(input: String, output: String, width: Int, height: Int, videoBitrate: String)
    case thumbnail(input: String, output: String, atSeconds: Double)

    public func validated(allowedRoot: URL) throws -> VideoOperation {
        switch self {
        case .inspect(let path):
            try Self.assertSafePathComponent(path, label: "inspect.path")
            let p = try PathSafety.resolveContainedPath(path: path, root: allowedRoot)
            return .inspect(path: p.path)
        case .trim(let input, let output, let start, let duration):
            guard start >= 0, duration > 0 else { throw AppError.validation("Invalid trim range") }
            try Self.assertSafePathComponent(input, label: "trim.input")
            try Self.assertSafePathComponent(output, label: "trim.output")
            let i = try PathSafety.resolveContainedPath(path: input, root: allowedRoot)
            let o = try PathSafety.resolveContainedPath(path: output, root: allowedRoot)
            return .trim(input: i.path, output: o.path, startSeconds: start, durationSeconds: duration)
        case .concatenate(let inputs, let output):
            guard inputs.count >= 2 else { throw AppError.validation("Concatenate requires >= 2 inputs") }
            for (idx, input) in inputs.enumerated() {
                try Self.assertSafePathComponent(input, label: "concatenate.input[\(idx)]")
            }
            try Self.assertSafePathComponent(output, label: "concatenate.output")
            let resolved = try inputs.map { try PathSafety.resolveContainedPath(path: $0, root: allowedRoot).path }
            let o = try PathSafety.resolveContainedPath(path: output, root: allowedRoot)
            return .concatenate(inputs: resolved, output: o.path)
        case .extractAudio(let input, let output):
            try Self.assertSafePathComponent(input, label: "extractAudio.input")
            try Self.assertSafePathComponent(output, label: "extractAudio.output")
            let i = try PathSafety.resolveContainedPath(path: input, root: allowedRoot)
            let o = try PathSafety.resolveContainedPath(path: output, root: allowedRoot)
            return .extractAudio(input: i.path, output: o.path)
        case .replaceAudio(let video, let audio, let output):
            try Self.assertSafePathComponent(video, label: "replaceAudio.video")
            try Self.assertSafePathComponent(audio, label: "replaceAudio.audio")
            try Self.assertSafePathComponent(output, label: "replaceAudio.output")
            let v = try PathSafety.resolveContainedPath(path: video, root: allowedRoot)
            let a = try PathSafety.resolveContainedPath(path: audio, root: allowedRoot)
            let o = try PathSafety.resolveContainedPath(path: output, root: allowedRoot)
            return .replaceAudio(video: v.path, audio: a.path, output: o.path)
        case .overlaySubtitles(let input, let srt, let output):
            try Self.assertSafePathComponent(input, label: "overlaySubtitles.input")
            try Self.assertSafePathComponent(srt, label: "overlaySubtitles.srt")
            try Self.assertSafePathComponent(output, label: "overlaySubtitles.output")
            let i = try PathSafety.resolveContainedPath(path: input, root: allowedRoot)
            let s = try PathSafety.resolveContainedPath(path: srt, root: allowedRoot)
            let o = try PathSafety.resolveContainedPath(path: output, root: allowedRoot)
            return .overlaySubtitles(input: i.path, srtPath: s.path, output: o.path)
        case .exportVertical(let input, let output, let width, let height, let bitrate):
            guard width > 0, height > 0 else { throw AppError.validation("Invalid resolution") }
            try PathSafety.assertNoShellMetacharacters(bitrate, label: "bitrate")
            try Self.assertSafePathComponent(input, label: "exportVertical.input")
            try Self.assertSafePathComponent(output, label: "exportVertical.output")
            let i = try PathSafety.resolveContainedPath(path: input, root: allowedRoot)
            let o = try PathSafety.resolveContainedPath(path: output, root: allowedRoot)
            return .exportVertical(input: i.path, output: o.path, width: width, height: height, videoBitrate: bitrate)
        case .thumbnail(let input, let output, let at):
            guard at >= 0 else { throw AppError.validation("Invalid thumbnail timestamp") }
            try Self.assertSafePathComponent(input, label: "thumbnail.input")
            try Self.assertSafePathComponent(output, label: "thumbnail.output")
            let i = try PathSafety.resolveContainedPath(path: input, root: allowedRoot)
            let o = try PathSafety.resolveContainedPath(path: output, root: allowedRoot)
            return .thumbnail(input: i.path, output: o.path, atSeconds: at)
        }
    }

    private static func assertSafePathComponent(_ path: String, label: String) throws {
        try PathSafety.assertNoShellMetacharacters(path, label: label)
    }

    /// Build argv for ffmpeg/ffprobe — never accept raw LLM argv.
    public func ffmpegArguments(ffprobe: Bool = false) throws -> (executableHint: String, args: [String]) {
        switch self {
        case .inspect(let path):
            return ("ffprobe", [
                "-v", "quiet",
                "-print_format", "json",
                "-show_format",
                "-show_streams",
                path
            ])
        case .trim(let input, let output, let start, let duration):
            // Re-encode for accurate cuts on short clips (stream-copy is keyframe-aligned only).
            return ("ffmpeg", [
                "-y", "-ss", String(start), "-i", input, "-t", String(duration),
                "-c:v", "libx264", "-preset", "veryfast", "-c:a", "aac",
                "-movflags", "+faststart",
                output
            ])
        case .concatenate(let inputs, let output):
            // Demuxer concat via list file is prepared by FFmpegEngine; argv here is a placeholder.
            // Engine replaces this with: -f concat -safe 0 -i <list> -c:v libx264 -c:a aac ...
            _ = inputs
            return ("ffmpeg", [
                "-y", "-f", "concat", "-safe", "0", "-i", "__CONCAT_LIST__",
                "-c:v", "libx264", "-preset", "veryfast", "-c:a", "aac",
                "-movflags", "+faststart",
                output
            ])
        case .extractAudio(let input, let output):
            // Re-encode audio for container compatibility (copy often fails across formats).
            return ("ffmpeg", ["-y", "-i", input, "-vn", "-c:a", "aac", "-b:a", "192k", output])
        case .replaceAudio(let video, let audio, let output):
            return ("ffmpeg", [
                "-y", "-i", video, "-i", audio,
                "-c:v", "copy", "-map", "0:v:0", "-map", "1:a:0",
                "-c:a", "aac", "-shortest",
                "-movflags", "+faststart",
                output
            ])
        case .overlaySubtitles(let input, let srt, let output):
            // Escape path for subtitles filter carefully — path already validated.
            let escaped = srt.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ":", with: "\\:")
            return ("ffmpeg", [
                "-y", "-i", input,
                "-vf", "subtitles=\(escaped)",
                "-c:a", "aac",
                "-movflags", "+faststart",
                output
            ])
        case .exportVertical(let input, let output, let width, let height, let bitrate):
            return ("ffmpeg", [
                "-y", "-i", input,
                "-vf", "scale=\(width):\(height):force_original_aspect_ratio=decrease,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2",
                "-b:v", bitrate,
                "-c:v", "libx264", "-preset", "veryfast",
                "-c:a", "aac",
                "-movflags", "+faststart",
                output
            ])
        case .thumbnail(let input, let output, let at):
            return ("ffmpeg", ["-y", "-ss", String(at), "-i", input, "-frames:v", "1", "-q:v", "2", output])
        }
    }
}

public struct VideoEditPlan: Sendable, Equatable, Codable {
    public var operations: [VideoOperation]
    public var requiresApproval: Bool

    public init(operations: [VideoOperation], requiresApproval: Bool = true) {
        self.operations = operations
        self.requiresApproval = requiresApproval
    }

    public func validated(allowedRoot: URL) throws -> VideoEditPlan {
        let ops = try operations.map { try $0.validated(allowedRoot: allowedRoot) }
        return VideoEditPlan(operations: ops, requiresApproval: requiresApproval)
    }
}
