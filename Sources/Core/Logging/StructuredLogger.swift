import Foundation
import os

public enum LogLevel: String, Sendable, Comparable {
    case debug, info, warning, error

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        rank(lhs) < rank(rhs)
    }

    private static func rank(_ level: LogLevel) -> Int {
        switch level {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }
}

public protocol Logger: Sendable {
    func log(_ level: LogLevel, _ message: String, metadata: [String: String])
}

public extension Logger {
    func debug(_ message: String, metadata: [String: String] = [:]) {
        log(.debug, message, metadata: metadata)
    }

    func info(_ message: String, metadata: [String: String] = [:]) {
        log(.info, message, metadata: metadata)
    }

    func warning(_ message: String, metadata: [String: String] = [:]) {
        log(.warning, message, metadata: metadata)
    }

    func error(_ message: String, metadata: [String: String] = [:]) {
        log(.error, message, metadata: metadata)
    }
}

public struct StructuredLogger: Logger {
    private let subsystem: String
    private let category: String
    private let minimumLevel: LogLevel
    private let osLog: OSLog

    public init(
        subsystem: String = "com.instagramaistudio",
        category: String = "backend",
        minimumLevel: LogLevel = .info
    ) {
        self.subsystem = subsystem
        self.category = category
        self.minimumLevel = minimumLevel
        self.osLog = OSLog(subsystem: subsystem, category: category)
    }

    public func log(_ level: LogLevel, _ message: String, metadata: [String: String]) {
        guard level >= minimumLevel else { return }
        let redacted = Self.redact(message)
        let meta = metadata
            .map { "\($0.key)=\(Self.redact($0.value))" }
            .sorted()
            .joined(separator: " ")
        let line = meta.isEmpty ? redacted : "\(redacted) | \(meta)"
        let type: OSLogType
        switch level {
        case .debug: type = .debug
        case .info: type = .info
        case .warning: type = .default
        case .error: type = .error
        }
        os_log("%{public}@", log: osLog, type: type, line)
    }

    /// Prevent accidental secret leakage into logs.
    public static func redact(_ text: String) -> String {
        var result = text
        let labeled = #"(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|authorization|bearer|telegram_bot_token)[=:\s]+[^\s,;\"']+"#
        let rawTokens = #"(?i)\b(sk-ant-[A-Za-z0-9_-]+|IGQ[A-Za-z0-9]+|EAA[A-Za-z0-9]+)\b"#
        if let regex = try? NSRegularExpression(pattern: labeled) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1=[REDACTED]")
        }
        if let regex = try? NSRegularExpression(pattern: rawTokens) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[REDACTED]")
        }
        return result
    }
}

public final class RecordingLogger: Logger, @unchecked Sendable {
    public struct Entry: Sendable, Equatable {
        public let level: LogLevel
        public let message: String
        public let metadata: [String: String]
    }

    private let lock = NSLock()
    private var _entries: [Entry] = []

    public init() {}

    public var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return _entries
    }

    public func log(_ level: LogLevel, _ message: String, metadata: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        _entries.append(Entry(level: level, message: StructuredLogger.redact(message), metadata: metadata))
    }
}
