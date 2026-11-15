import XCTest
@testable import Jobs
@testable import Persistence
@testable import Core

final class JobsTests: XCTestCase {
    func testJobLifecycleAndCancel() async throws {
        let db = try DatabaseManager.inMemory()
        let repo = JobRepository(db: db)
        let audit = AuditLogRepository(db: db)
        let coordinator = JobCoordinator(repository: repo, audit: audit, logger: StructuredLogger(minimumLevel: .error))
        await coordinator.register(SlowJobHandler())
        let job = try await coordinator.submit(kind: "slow", payloadJSON: "{}")
        try await coordinator.enqueue(job.id)
        try await Task.sleep(nanoseconds: 50_000_000)
        try await coordinator.cancel(job.id)
        let status = try await coordinator.status(job.id)
        XCTAssertTrue(status.state == .cancelled || status.state == .completed || status.state == .failed)
    }

    func testRecoveryMarksRunningFailed() async throws {
        let db = try DatabaseManager.inMemory()
        let repo = JobRepository(db: db)
        let job = JobRecord(kind: "slow", state: .running, payloadJSON: "{}")
        try repo.insert(job)
        let coordinator = JobCoordinator(repository: repo, audit: AuditLogRepository(db: db), logger: StructuredLogger(minimumLevel: .error))
        try await coordinator.recoverIncomplete()
        let loaded = try repo.get(id: job.id)
        XCTAssertEqual(loaded?.state, .failed)
    }
}

struct SlowJobHandler: JobHandler {
    var kind: String { "slow" }
    func run(job: JobRecord, progress: @escaping @Sendable (Double, String?) async -> Void) async throws -> String {
        for i in 0..<20 {
            try Task.checkCancellation()
            await progress(Double(i) / 20.0, nil)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return "{}"
    }
}
