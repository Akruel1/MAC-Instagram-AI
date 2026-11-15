import Foundation

/// Bridges consequential tool approvals to a SwiftUI sheet via continuations.
public actor UIApprovalBroker: ApprovalBroker {
    public struct PendingApproval: Sendable, Identifiable, Equatable {
        public let request: ApprovalRequest
        public var id: UUID { request.id }
    }

    private var waiters: [UUID: CheckedContinuation<ApprovalDecision, Never>] = [:]
    private var pendingOrder: [PendingApproval] = []
    private var observers: [UUID: AsyncStream<PendingApproval?>.Continuation] = [:]

    public init() {}

    public func pendingApprovals() -> AsyncStream<PendingApproval?> {
        AsyncStream { continuation in
            let id = UUID()
            observers[id] = continuation
            continuation.yield(pendingOrder.first)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }

    public func requestApproval(_ request: ApprovalRequest) async throws -> ApprovalDecision {
        let pending = PendingApproval(request: request)
        pendingOrder.append(pending)
        publishHead()
        return await withCheckedContinuation { continuation in
            waiters[request.id] = continuation
        }
    }

    public func resolve(id: UUID, decision: ApprovalDecision) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        pendingOrder.removeAll { $0.id == id }
        waiter.resume(returning: decision)
        publishHead()
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func publishHead() {
        let head = pendingOrder.first
        for observer in observers.values {
            observer.yield(head)
        }
    }
}
