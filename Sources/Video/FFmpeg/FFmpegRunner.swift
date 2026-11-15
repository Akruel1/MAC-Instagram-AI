import Foundation
import Core

public protocol ProcessRunner: Sendable {
    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> (exitCode: Int32, stdout: Data, stderr: Data)
}

/// Launches executables via `Foundation.Process` (no shell). Honors Task cancellation by terminating the child.
public struct FoundationProcessRunner: ProcessRunner {
    public init() {}

    public func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> (exitCode: Int32, stdout: Data, stderr: Data) {
        try PathSafety.assertNoShellMetacharacters(executable, label: "executable")
        for arg in arguments {
            try PathSafety.assertNoShellMetacharacters(arg, label: "argument")
        }
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        return try await withTimeout(seconds: timeout) {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Int32, Data, Data), Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try process.run()
                            process.waitUntilExit()
                            let stdout = out.fileHandleForReading.readDataToEndOfFile()
                            let stderr = err.fileHandleForReading.readDataToEndOfFile()
                            if Task.isCancelled {
                                continuation.resume(throwing: CancellationError())
                            } else {
                                continuation.resume(returning: (process.terminationStatus, stdout, stderr))
                            }
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            } onCancel: {
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}

public enum KnownMediaToolPaths {
    /// Absolute paths for common package managers. Homebrew is not assumed exclusive.
    public static let ffmpegCandidates = [
        "/opt/local/bin/ffmpeg",      // MacPorts
        "/opt/homebrew/bin/ffmpeg",   // Homebrew (Apple Silicon)
        "/usr/local/bin/ffmpeg",      // Homebrew (Intel) / manual
        "/usr/bin/ffmpeg"
    ]

    public static let ffprobeCandidates = [
        "/opt/local/bin/ffprobe",
        "/opt/homebrew/bin/ffprobe",
        "/usr/local/bin/ffprobe",
        "/usr/bin/ffprobe"
    ]
}

public struct FFmpegLocator: Sendable {
    public var searchPaths: [String]

    public init(searchPaths: [String] = KnownMediaToolPaths.ffmpegCandidates) {
        self.searchPaths = searchPaths
    }

    public func findFFmpeg() -> String? {
        find(named: "ffmpeg", candidates: searchPaths)
    }

    public func findFFprobe() -> String? {
        let probePaths: [String]
        if searchPaths == KnownMediaToolPaths.ffmpegCandidates {
            probePaths = KnownMediaToolPaths.ffprobeCandidates
        } else {
            probePaths = searchPaths.map { $0.replacingOccurrences(of: "ffmpeg", with: "ffprobe") }
        }
        return find(named: "ffprobe", candidates: probePaths)
    }

    private func find(named: String, candidates: [String]) -> String? {
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [named]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}
        return nil
    }
}

public struct FFmpegEngine: Sendable {
    private let runner: ProcessRunner
    private let locator: FFmpegLocator
    private let timeout: TimeInterval

    public init(runner: ProcessRunner = FoundationProcessRunner(), locator: FFmpegLocator = FFmpegLocator(), timeout: TimeInterval = 600) {
        self.runner = runner
        self.locator = locator
        self.timeout = timeout
    }

    public var isAvailable: Bool { locator.findFFmpeg() != nil }

    public func inspect(path: String) async throws -> MediaInspection {
        guard let ffprobe = locator.findFFprobe() else {
            throw AppError.dependency("ffprobe not found")
        }
        try Task.checkCancellation()
        let op = VideoOperation.inspect(path: path)
        let (_, args) = try op.ffmpegArguments()
        let result = try await runner.run(executable: ffprobe, arguments: args, timeout: timeout)
        guard result.exitCode == 0 else {
            let err = String(data: result.stderr, encoding: .utf8) ?? ""
            throw AppError.external(service: "ffprobe", message: err)
        }
        return try parseProbe(path: path, data: result.stdout)
    }

    public func execute(_ operation: VideoOperation) async throws {
        try Task.checkCancellation()
        if case .inspect = operation {
            _ = try await inspect(path: {
                if case .inspect(let p) = operation { return p }
                return ""
            }())
            return
        }
        guard let ffmpeg = locator.findFFmpeg() else {
            throw AppError.dependency(
                "ffmpeg not found. Checked MacPorts (/opt/local/bin), Homebrew, /usr/local/bin, PATH. Install via MacPorts (`sudo port install ffmpeg`) or Homebrew (`brew install ffmpeg`)."
            )
        }

        var listURL: URL?
        defer {
            if let listURL {
                try? FileManager.default.removeItem(at: listURL)
            }
        }

        var args: [String]
        if case .concatenate(let inputs, let output) = operation {
            let list = URL(fileURLWithPath: output).deletingLastPathComponent()
                .appendingPathComponent("concat-\(UUID().uuidString).txt")
            let body = inputs.map { path -> String in
                let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
                return "file '\(escaped)'"
            }.joined(separator: "\n")
            try body.write(to: list, atomically: true, encoding: .utf8)
            listURL = list
            args = [
                "-y", "-f", "concat", "-safe", "0", "-i", list.path,
                "-c:v", "libx264", "-preset", "veryfast", "-c:a", "aac",
                "-movflags", "+faststart",
                output
            ]
        } else {
            (_, args) = try operation.ffmpegArguments()
        }

        do {
            let result = try await runner.run(executable: ffmpeg, arguments: args, timeout: timeout)
            guard result.exitCode == 0 else {
                let err = String(data: result.stderr, encoding: .utf8) ?? "ffmpeg failed"
                throw AppError.external(service: "ffmpeg", message: err)
            }
        } catch is CancellationError {
            // Best-effort cleanup of partial outputs.
            if let outputPath = Self.outputPath(of: operation) {
                try? FileManager.default.removeItem(atPath: outputPath)
            }
            throw CancellationError()
        }

        if let outputPath = Self.outputPath(of: operation) {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: outputPath, isDirectory: &isDir), !isDir.boolValue else {
                throw AppError.external(service: "ffmpeg", message: "Expected output missing: \(outputPath)")
            }
            let attrs = try FileManager.default.attributesOfItem(atPath: outputPath)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0 else {
                throw AppError.external(service: "ffmpeg", message: "Output file is empty: \(outputPath)")
            }
        }
    }

    private static func outputPath(of operation: VideoOperation) -> String? {
        switch operation {
        case .inspect: return nil
        case .trim(_, let output, _, _): return output
        case .concatenate(_, let output): return output
        case .extractAudio(_, let output): return output
        case .replaceAudio(_, _, let output): return output
        case .overlaySubtitles(_, _, let output): return output
        case .exportVertical(_, let output, _, _, _): return output
        case .thumbnail(_, let output, _): return output
        }
    }

    private func parseProbe(path: String, data: Data) throws -> MediaInspection {
        struct Probe: Decodable {
            struct Stream: Decodable {
                let codec_type: String?
                let width: Int?
                let height: Int?
            }
            struct Format: Decodable {
                let duration: String?
                let format_name: String?
            }
            let streams: [Stream]?
            let format: Format?
        }
        let probe = try JSONDecoder().decode(Probe.self, from: data)
        let video = probe.streams?.first(where: { $0.codec_type == "video" })
        let hasAudio = probe.streams?.contains(where: { $0.codec_type == "audio" }) ?? false
        let duration = probe.format?.duration.flatMap(Double.init)
        let width = video?.width
        let height = video?.height
        let aspect: String?
        if let width, let height, height != 0 {
            let g = gcd(width, height)
            aspect = "\(width / g):\(height / g)"
        } else {
            aspect = nil
        }
        return MediaInspection(
            path: path,
            durationSeconds: duration,
            width: width,
            height: height,
            aspectRatio: aspect,
            hasAudio: hasAudio,
            format: probe.format?.format_name
        )
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var a = abs(a), b = abs(b)
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }
}
