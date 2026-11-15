import Foundation

public func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw AppError.timeout("Operation exceeded \(seconds)s")
        }
        guard let result = try await group.next() else {
            throw AppError.cancelled
        }
        group.cancelAll()
        return result
    }
}

public struct RetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval
    public var jitterFraction: Double

    public init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 0.5,
        maxDelay: TimeInterval = 8,
        jitterFraction: Double = 0.2
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterFraction = jitterFraction
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let exp = min(maxDelay, baseDelay * pow(2, Double(max(0, attempt - 1))))
        let jitter = exp * jitterFraction * Double.random(in: -1...1)
        return max(0, exp + jitter)
    }
}

public func withRetry<T: Sendable>(
    policy: RetryPolicy = RetryPolicy(),
    shouldRetry: @escaping @Sendable (Error) -> Bool = { ($0 as? AppError).map { if case .rateLimited = $0 { return true }; if case .network = $0 { return true }; return false } ?? false },
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    var lastError: Error?
    for attempt in 1...policy.maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            if attempt == policy.maxAttempts || !shouldRetry(error) {
                throw error
            }
            let delay = policy.delay(forAttempt: attempt)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
    throw lastError ?? AppError.network("Retry exhausted")
}
