import Foundation
import Core

public enum ToolPermissionCategory: String, Sendable, Codable, CaseIterable, Equatable {
    case readOnlyFileAccess = "read_only_file_access"
    case restrictedFileWrites = "restricted_file_writes"
    case mediaProcessing = "media_processing"
    case networkAccess = "network_access"
    case instagramAnalytics = "instagram_analytics"
    case instagramPublishing = "instagram_publishing"
    case externalProcessExecution = "external_process_execution"
}

public struct ToolPermissionPolicy: Sendable, Equatable {
    public var allowedCategories: Set<ToolPermissionCategory>
    public var categoriesRequiringApproval: Set<ToolPermissionCategory>
    public var allowedRoots: [URL]

    public init(
        allowedCategories: Set<ToolPermissionCategory> = Set(ToolPermissionCategory.allCases).subtracting([.instagramPublishing]),
        categoriesRequiringApproval: Set<ToolPermissionCategory> = [
            .restrictedFileWrites,
            .instagramPublishing,
            .externalProcessExecution,
            .mediaProcessing
        ],
        allowedRoots: [URL] = []
    ) {
        self.allowedCategories = allowedCategories
        self.categoriesRequiringApproval = categoriesRequiringApproval
        self.allowedRoots = allowedRoots
    }
}

public struct ToolPermissionGate: Sendable {
    public var policy: ToolPermissionPolicy
    private let approvalBroker: any ApprovalBroker

    public init(policy: ToolPermissionPolicy, approvalBroker: any ApprovalBroker) {
        self.policy = policy
        self.approvalBroker = approvalBroker
    }

    public func authorize(
        toolName: String,
        category: ToolPermissionCategory,
        summary: String,
        details: [String: String] = [:]
    ) async throws {
        guard policy.allowedCategories.contains(category) else {
            throw AppError.permissionDenied("Category \(category.rawValue) is not allowed for tool \(toolName)")
        }
        if policy.categoriesRequiringApproval.contains(category) {
            let decision = try await approvalBroker.requestApproval(
                ApprovalRequest(
                    category: category.rawValue,
                    action: toolName,
                    summary: summary,
                    details: details
                )
            )
            if decision != .approved {
                throw AppError.permissionDenied("User denied tool \(toolName)")
            }
        }
    }

    public func validatePath(_ path: String) throws -> URL {
        guard !policy.allowedRoots.isEmpty else {
            throw AppError.permissionDenied("No filesystem roots configured")
        }
        var lastError: Error = AppError.unsafeOperation("Path not in allowed roots")
        for root in policy.allowedRoots {
            do {
                return try PathSafety.resolveContainedPath(path: path, root: root)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
