import Foundation
import Core
import Persistence

public struct JobProgressEvent: Sendable, Equatable {
    public let jobId: String
    public let state: JobState
    public let progress: Double
    public let message: String?

    public init(jobId: String, state: JobState, progress: Double, message: String? = nil) {
        self.jobId = jobId
        self.state = state
        self.progress = progress
        self.message = message
    }
}

public protocol JobHandler: Sendable {
    var kind: String { get }
    func run(job: JobRecord, progress: @escaping @Sendable (Double, String?) async -> Void) async throws -> String
}

public actor JobCoordinator {
    private let repository: JobRepository
    private let audit: AuditLogRepository
    private let logger: Logger
    private var handlers: [String: JobHandler] = [:]
    private var runningTasks: [String: Task<Void, Never>] = [:]
    private var continuations: [UUID: AsyncStream<JobProgressEvent>.Continuation] = [:]

    public init(repository: JobRepository, audit: AuditLogRepository, logger: Logger) {
        self.repository = repository
        self.audit = audit
        self.logger = logger
    }

    public func register(_ handler: JobHandler) {
        handlers[handler.kind] = handler
    }

    public func progressStream() -> AsyncStream<JobProgressEvent> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func publish(_ event: JobProgressEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    public func submit(kind: String, payloadJSON: String) throws -> JobRecord {
        guard handlers[kind] != nil else {
            throw AppError.validation("No handler for job kind: \(kind)")
        }
        let job = JobRecord(kind: kind, state: .pending, payloadJSON: payloadJSON)
        try repository.insert(job)
        try audit.append(AuditLogEntry(category: "jobs", action: "submit", details: ["jobId": job.id, "kind": kind]))
        return job
    }

    public func enqueue(_ jobId: String) async throws {
        guard var job = try repository.get(id: jobId) else {
            throw AppError.notFound("Job \(jobId)")
        }
        guard let handler = handlers[job.kind] else {
            throw AppError.validation("No handler for \(job.kind)")
        }
        job.state = .queued
        job.updatedAt = Date()
        try repository.update(job)
        publish(JobProgressEvent(jobId: job.id, state: .queued, progress: job.progress))

        let task = Task { [weak self] in
            await self?.execute(jobId: jobId, handler: handler)
            return
        }
        runningTasks[jobId] = task
    }

    public func cancel(_ jobId: String) async throws {
        runningTasks[jobId]?.cancel()
        guard var job = try repository.get(id: jobId) else {
            throw AppError.notFound("Job \(jobId)")
        }
        if !job.state.isTerminal {
            job.state = .cancelled
            job.updatedAt = Date()
            job.finishedAt = Date()
            try repository.update(job)
            publish(JobProgressEvent(jobId: jobId, state: .cancelled, progress: job.progress, message: "Cancelled"))
        }
    }

    public func recoverIncomplete() async throws {
        let jobs = try repository.incomplete()
        for job in jobs where job.state == .running || job.state == .queued {
            var failed = job
            failed.state = .failed
            failed.errorMessage = "Interrupted by application restart"
            failed.updatedAt = Date()
            failed.finishedAt = Date()
            try repository.update(failed)
            publish(JobProgressEvent(jobId: failed.id, state: .failed, progress: failed.progress, message: failed.errorMessage))
        }
    }

    public func status(_ jobId: String) throws -> JobRecord {
        guard let job = try repository.get(id: jobId) else {
            throw AppError.notFound("Job \(jobId)")
        }
        return job
    }

    public func recent(limit: Int = 20) throws -> [JobRecord] {
        try repository.recent(limit: limit)
    }

    private func execute(jobId: String, handler: JobHandler) async {
        do {
            guard var job = try repository.get(id: jobId) else { return }
            job.state = .validating
            job.updatedAt = Date()
            try repository.update(job)
            publish(JobProgressEvent(jobId: jobId, state: .validating, progress: 0))

            job.state = .running
            job.startedAt = Date()
            job.attemptCount += 1
            job.updatedAt = Date()
            try repository.update(job)
            publish(JobProgressEvent(jobId: jobId, state: .running, progress: 0))

            let result = try await handler.run(job: job) { [weak self] progress, message in
                guard let self else { return }
                try? await self.updateProgress(jobId: jobId, progress: progress, message: message)
            }

            if Task.isCancelled {
                try await mark(jobId: jobId, state: .cancelled, result: nil, error: "Cancelled")
                return
            }

            try await mark(jobId: jobId, state: .completed, result: result, error: nil)
        } catch is CancellationError {
            try? await mark(jobId: jobId, state: .cancelled, result: nil, error: "Cancelled")
        } catch {
            try? await mark(jobId: jobId, state: .failed, result: nil, error: error.localizedDescription)
        }
        runningTasks[jobId] = nil
    }

    private func updateProgress(jobId: String, progress: Double, message: String?) async throws {
        guard var job = try repository.get(id: jobId) else { return }
        job.progress = min(1, max(0, progress))
        job.updatedAt = Date()
        try repository.update(job)
        publish(JobProgressEvent(jobId: jobId, state: .running, progress: job.progress, message: message))
    }

    private func mark(jobId: String, state: JobState, result: String?, error: String?) async throws {
        guard var job = try repository.get(id: jobId) else { return }
        // Do not resurrect a cancelled job as completed/failed from a racing finish.
        if job.state == .cancelled, state == .completed {
            return
        }
        job.state = state
        job.resultJSON = result
        job.errorMessage = error
        job.updatedAt = Date()
        job.finishedAt = Date()
        if state == .completed { job.progress = 1 }
        try repository.update(job)
        publish(JobProgressEvent(jobId: jobId, state: state, progress: job.progress, message: error))
        try audit.append(
            AuditLogEntry(
                category: "jobs",
                action: state.rawValue.lowercased(),
                details: ["jobId": jobId, "error": error ?? ""]
            )
        )
    }
}
