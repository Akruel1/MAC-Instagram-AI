import Foundation
import Core
import Persistence
import Jobs

public struct VideoJobHandler: JobHandler {
    public let kind = "video.render"
    private let engine: FFmpegEngine
    private let allowedRoot: URL
    private let approvalBroker: any ApprovalBroker

    public init(engine: FFmpegEngine, allowedRoot: URL, approvalBroker: any ApprovalBroker) {
        self.engine = engine
        self.allowedRoot = allowedRoot
        self.approvalBroker = approvalBroker
    }

    public func run(job: JobRecord, progress: @escaping @Sendable (Double, String?) async -> Void) async throws -> String {
        guard engine.isAvailable else {
            throw AppError.dependency("FFmpeg is not installed")
        }
        let plan = try JSONDecoder().decode(VideoEditPlan.self, from: Data(job.payloadJSON.utf8))
        let validated = try plan.validated(allowedRoot: allowedRoot)
        if validated.requiresApproval {
            let decision = try await approvalBroker.requestApproval(
                ApprovalRequest(
                    category: ToolPermissionCategoryLike.media,
                    action: "video.render",
                    summary: "Execute \(validated.operations.count) video operation(s)",
                    details: ["jobId": job.id]
                )
            )
            if decision != .approved {
                throw AppError.permissionDenied("Video render denied")
            }
        }
        let total = Double(max(validated.operations.count, 1))
        var outputs: [String] = []
        for (index, op) in validated.operations.enumerated() {
            try Task.checkCancellation()
            await progress(Double(index) / total, "Running operation \(index + 1)/\(validated.operations.count)")
            try await engine.execute(op)
            if case .trim(_, let output, _, _) = op { outputs.append(output) }
            else if case .concatenate(_, let output) = op { outputs.append(output) }
            else if case .extractAudio(_, let output) = op { outputs.append(output) }
            else if case .replaceAudio(_, _, let output) = op { outputs.append(output) }
            else if case .overlaySubtitles(_, _, let output) = op { outputs.append(output) }
            else if case .exportVertical(_, let output, _, _, _) = op { outputs.append(output) }
            else if case .thumbnail(_, let output, _) = op { outputs.append(output) }
        }
        await progress(1, "Completed")
        let result = ["outputs": outputs]
        let data = try JSONEncoder().encode(result)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private enum ToolPermissionCategoryLike {
    static let media = "media_processing"
}

public protocol RemotionRenderer: Sendable {
    var isAvailable: Bool { get }
    func render(compositionID: String, propsJSON: String, output: URL) async throws
}

public struct UnavailableRemotionRenderer: RemotionRenderer {
    public init() {}
    public var isAvailable: Bool { false }
    public func render(compositionID: String, propsJSON: String, output: URL) async throws {
        throw AppError.dependency(
            "Remotion is optional and not configured. It requires an isolated Node.js runtime adapter."
        )
    }
}
