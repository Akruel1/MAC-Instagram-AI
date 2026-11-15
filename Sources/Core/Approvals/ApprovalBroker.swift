import Foundation

public enum ApprovalDecision: String, Sendable, Codable, Equatable {
    case approved
    case denied
}

public struct ApprovalRequest: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let category: String
    public let action: String
    public let summary: String
    public let details: [String: String]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        category: String,
        action: String,
        summary: String,
        details: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.action = action
        self.summary = summary
        self.details = details
        self.createdAt = createdAt
    }
}

public protocol ApprovalBroker: Sendable {
    func requestApproval(_ request: ApprovalRequest) async throws -> ApprovalDecision
}

/// Auto-denies consequential actions unless explicitly allowlisted (safe default for tests).
public actor DenyByDefaultApprovalBroker: ApprovalBroker {
    private var allowAll = false

    public init(allowAll: Bool = false) {
        self.allowAll = allowAll
    }

    public func setAllowAll(_ value: Bool) {
        allowAll = value
    }

    public func requestApproval(_ request: ApprovalRequest) async throws -> ApprovalDecision {
        allowAll ? .approved : .denied
    }
}

/// Interactive CLI approval via stdin.
public struct CLIApprovalBroker: ApprovalBroker {
    public init() {}

    public func requestApproval(_ request: ApprovalRequest) async throws -> ApprovalDecision {
        print("\n=== APPROVAL REQUIRED ===")
        print("Category: \(request.category)")
        print("Action: \(request.action)")
        print("Summary: \(request.summary)")
        if !request.details.isEmpty {
            print("Details:")
            for (k, v) in request.details.sorted(by: { $0.key < $1.key }) {
                print("  \(k): \(v)")
            }
        }
        print("Approve? [y/N]: ", terminator: "")
        fflush(stdout)
        let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "n"
        return (line == "y" || line == "yes") ? .approved : .denied
    }
}
