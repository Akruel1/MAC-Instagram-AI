import Darwin
import Foundation

/// Thin wrapper around `os_unfair_lock` for shared mutable state accessed from async code.
/// Prefer this over `NSLock` under Swift 6 concurrency checking.
public final class UnfairLockBox<Value>: @unchecked Sendable {
    private var value: Value
    private var unfair = os_unfair_lock_s()

    public init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    public func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        os_unfair_lock_lock(&unfair)
        defer { os_unfair_lock_unlock(&unfair) }
        return try body(&value)
    }
}
