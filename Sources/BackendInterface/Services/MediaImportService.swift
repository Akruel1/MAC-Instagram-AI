import Foundation
import Core
import Video

public struct MediaImportResult: Sendable, Equatable {
    public var managedURL: URL
    public var inspection: MediaInspection

    public init(managedURL: URL, inspection: MediaInspection) {
        self.managedURL = managedURL
        self.inspection = inspection
    }
}

/// Copies external media into the managed Media directory and inspects it. Never loads whole files into memory.
public struct MediaImportService: Sendable {
    private let mediaRoot: URL
    private let engine: FFmpegEngine
    private let allowedExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv"]

    public init(mediaRoot: URL, engine: FFmpegEngine = FFmpegEngine()) {
        self.mediaRoot = mediaRoot
        self.engine = engine
    }

    public func importAndInspect(from sourceURL: URL) async throws -> MediaImportResult {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { sourceURL.stopAccessingSecurityScopedResource() }
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw AppError.notFound("Source media missing: \(sourceURL.lastPathComponent)")
        }

        let ext = sourceURL.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw AppError.validation("Unsupported media type: .\(ext.isEmpty ? "(none)" : ext)")
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDir), !isDir.boolValue else {
            throw AppError.validation("Selected item is not a file")
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            throw AppError.validation("Media file is empty")
        }

        try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)

        let safeBase = sanitizeFilename(sourceURL.deletingPathExtension().lastPathComponent)
        let destName = "\(safeBase)-\(UUID().uuidString.prefix(8)).\(ext)"
        let dest = mediaRoot.appendingPathComponent(destName)

        do {
            // Streamed copy via FileManager — does not load the entire file into memory.
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        } catch {
            throw AppError.persistence("Failed to copy media into managed library: \(error.localizedDescription)")
        }

        do {
            let inspection = try await engine.inspect(path: dest.path)
            if inspection.durationSeconds == nil && inspection.width == nil {
                // ffprobe succeeded but yielded nothing useful — treat as unsupported/corrupt.
                try? FileManager.default.removeItem(at: dest)
                throw AppError.validation("Could not read media metadata. File may be corrupt or unsupported.")
            }
            return MediaImportResult(managedURL: dest, inspection: inspection)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.isEmpty ? "clip" : trimmed
        // Keep Unicode letters/numbers; replace path separators only.
        let cleaned = collapsed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return String(cleaned.prefix(80))
    }
}
