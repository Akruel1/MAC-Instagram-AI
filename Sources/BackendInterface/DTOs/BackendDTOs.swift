import Foundation
import Core
import Persistence
import Instagram
import Jobs
import Hermes
import Dependencies
import AI

public enum BackendEvent: Sendable, Equatable {
    case log(level: String, message: String)
    case jobProgress(JobProgressEvent)
    case chatDelta(conversationId: String, text: String)
    case toolApproval(ApprovalRequest)
    case featureAvailability(FeatureAvailability)
    case diagnostic(String)
}

public struct OnboardingStatusDTO: Sendable, Equatable, Codable {
    public var claudeConfigured: Bool
    public var instagramAuthenticated: Bool
    public var dependenciesReady: Bool
    public var hermesOptionalReady: Bool
    public var onboardingCompleted: Bool
    public var incompleteSteps: [String]

    public init(
        claudeConfigured: Bool,
        instagramAuthenticated: Bool,
        dependenciesReady: Bool,
        hermesOptionalReady: Bool,
        onboardingCompleted: Bool = false,
        incompleteSteps: [String]
    ) {
        self.claudeConfigured = claudeConfigured
        self.instagramAuthenticated = instagramAuthenticated
        self.dependenciesReady = dependenciesReady
        self.hermesOptionalReady = hermesOptionalReady
        self.onboardingCompleted = onboardingCompleted
        self.incompleteSteps = incompleteSteps
    }
}

public struct LinkedInstagramAccountDTO: Sendable, Equatable, Codable {
    public var userID: String?
    public var authenticated: Bool
    public var tokenExpired: Bool
    public var note: String

    public init(userID: String?, authenticated: Bool, tokenExpired: Bool, note: String) {
        self.userID = userID
        self.authenticated = authenticated
        self.tokenExpired = tokenExpired
        self.note = note
    }
}

public struct RecentJobDTO: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var kind: String
    public var state: String
    public var progress: Double
    public var errorMessage: String?
    public var updatedAt: Date

    public init(id: String, kind: String, state: String, progress: Double, errorMessage: String?, updatedAt: Date) {
        self.id = id
        self.kind = kind
        self.state = state
        self.progress = progress
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }
}

public struct AnalyticsSyncResultDTO: Sendable, Equatable, Codable {
    public var success: Bool
    public var accountId: String?
    public var persistedCount: Int
    public var note: String

    public init(success: Bool, accountId: String?, persistedCount: Int, note: String) {
        self.success = success
        self.accountId = accountId
        self.persistedCount = persistedCount
        self.note = note
    }
}

public struct ChatMessageDTO: Sendable, Equatable, Codable {
    public var id: String
    public var conversationId: String
    public var role: String
    public var text: String
    public var createdAt: Date

    public init(id: String, conversationId: String, role: String, text: String, createdAt: Date) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public struct DiagnosticsDTO: Sendable, Equatable, Codable {
    public var features: FeatureAvailability
    public var system: SystemProfile
    public var hermes: HermesStatus
    public var databasePath: String

    public init(
        features: FeatureAvailability,
        system: SystemProfile,
        hermes: HermesStatus,
        databasePath: String
    ) {
        self.features = features
        self.system = system
        self.hermes = hermes
        self.databasePath = databasePath
    }
}
