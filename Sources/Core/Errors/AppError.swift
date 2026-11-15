import Foundation

public enum AppError: Error, Sendable, Equatable {
    case configuration(String)
    case validation(String)
    case authentication(String)
    case authorization(String)
    case permissionDenied(String)
    case notFound(String)
    case network(String)
    case rateLimited(retryAfter: TimeInterval?)
    case dependency(String)
    case persistence(String)
    case cancelled
    case timeout(String)
    case external(service: String, message: String)
    case incomplete(String)
    case unsafeOperation(String)
}

extension AppError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .configuration(let m): return "Configuration error: \(m)"
        case .validation(let m): return "Validation error: \(m)"
        case .authentication(let m): return "Authentication error: \(m)"
        case .authorization(let m): return "Authorization error: \(m)"
        case .permissionDenied(let m): return "Permission denied: \(m)"
        case .notFound(let m): return "Not found: \(m)"
        case .network(let m): return "Network error: \(m)"
        case .rateLimited(let retry):
            if let retry { return "Rate limited; retry after \(retry)s" }
            return "Rate limited"
        case .dependency(let m): return "Dependency error: \(m)"
        case .persistence(let m): return "Persistence error: \(m)"
        case .cancelled: return "Operation cancelled"
        case .timeout(let m): return "Timeout: \(m)"
        case .external(let service, let message): return "\(service): \(message)"
        case .incomplete(let m): return "Incomplete data: \(m)"
        case .unsafeOperation(let m): return "Unsafe operation blocked: \(m)"
        }
    }
}

public enum ErrorClassifier: Sendable {
    public static func classifyHTTP(status: Int, body: String?) -> AppError {
        switch status {
        case 401: return .authentication(body ?? "Unauthorized")
        case 403: return .authorization(body ?? "Forbidden")
        case 404: return .notFound(body ?? "Not found")
        case 429: return .rateLimited(retryAfter: nil)
        case 408: return .timeout(body ?? "Request timeout")
        case 400..<500: return .validation(body ?? "Client error \(status)")
        case 500..<600: return .network(body ?? "Server error \(status)")
        default: return .network("Unexpected HTTP \(status)")
        }
    }
}
