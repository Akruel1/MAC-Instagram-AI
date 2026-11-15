import Foundation

public struct AppConfiguration: Sendable, Equatable {
    public var applicationSupportDirectory: URL
    public var databaseFileName: String
    public var mediaDirectoryName: String
    public var tempDirectoryName: String
    public var logRetentionDays: Int
    public var tempMediaRetentionHours: Int
    public var defaultRequestTimeout: TimeInterval
    public var claudeDefaultModel: String
    public var claudeMaxTokens: Int
    public var claudeAPIBaseURL: URL
    public var instagramGraphBaseURL: URL
    public var instagramOAuthBaseURL: URL
    public var metaAppID: String?
    public var metaRedirectURI: String
    public var keychainService: String

    public init(
        applicationSupportDirectory: URL? = nil,
        databaseFileName: String = "studio.sqlite",
        mediaDirectoryName: String = "Media",
        tempDirectoryName: String = "Temp",
        logRetentionDays: Int = 30,
        tempMediaRetentionHours: Int = 72,
        defaultRequestTimeout: TimeInterval = 60,
        claudeDefaultModel: String = "claude-sonnet-4-5",
        claudeMaxTokens: Int = 4096,
        claudeAPIBaseURL: URL = URL(string: "https://api.anthropic.com")!,
        instagramGraphBaseURL: URL = URL(string: "https://graph.instagram.com")!,
        instagramOAuthBaseURL: URL = URL(string: "https://api.instagram.com")!,
        metaAppID: String? = nil,
        metaRedirectURI: String = "http://127.0.0.1:8765/oauth/callback",
        keychainService: String = "com.instagramaistudio"
    ) {
        if let applicationSupportDirectory {
            self.applicationSupportDirectory = applicationSupportDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.applicationSupportDirectory = base.appendingPathComponent("InstagramAIStudio", isDirectory: true)
        }
        self.databaseFileName = databaseFileName
        self.mediaDirectoryName = mediaDirectoryName
        self.tempDirectoryName = tempDirectoryName
        self.logRetentionDays = logRetentionDays
        self.tempMediaRetentionHours = tempMediaRetentionHours
        self.defaultRequestTimeout = defaultRequestTimeout
        self.claudeDefaultModel = claudeDefaultModel
        self.claudeMaxTokens = claudeMaxTokens
        self.claudeAPIBaseURL = claudeAPIBaseURL
        self.instagramGraphBaseURL = instagramGraphBaseURL
        self.instagramOAuthBaseURL = instagramOAuthBaseURL
        self.metaAppID = metaAppID ?? ProcessInfo.processInfo.environment["META_APP_ID"]
        self.metaRedirectURI = metaRedirectURI
        self.keychainService = keychainService
    }

    public var databaseURL: URL {
        applicationSupportDirectory.appendingPathComponent(databaseFileName)
    }

    public var mediaDirectoryURL: URL {
        applicationSupportDirectory.appendingPathComponent(mediaDirectoryName, isDirectory: true)
    }

    public var tempDirectoryURL: URL {
        applicationSupportDirectory.appendingPathComponent(tempDirectoryName, isDirectory: true)
    }

    public func validate() throws {
        guard !claudeDefaultModel.isEmpty else {
            throw AppError.configuration("claudeDefaultModel must not be empty")
        }
        guard claudeMaxTokens > 0 else {
            throw AppError.configuration("claudeMaxTokens must be positive")
        }
        guard defaultRequestTimeout > 0 else {
            throw AppError.configuration("defaultRequestTimeout must be positive")
        }
        guard logRetentionDays > 0 else {
            throw AppError.configuration("logRetentionDays must be positive")
        }
    }
}

public struct ModelCatalog: Sendable, Equatable {
    public var availableModels: [String]
    public var defaultModel: String

    public init(availableModels: [String], defaultModel: String) {
        self.availableModels = availableModels
        self.defaultModel = defaultModel
    }

    public static let `default` = ModelCatalog(
        availableModels: [
            "claude-sonnet-4-5",
            "claude-opus-4-5",
            "claude-haiku-4-5"
        ],
        defaultModel: "claude-sonnet-4-5"
    )

    public func resolve(_ preferred: String?) throws -> String {
        let model = preferred ?? defaultModel
        guard availableModels.contains(model) || preferred != nil else {
            throw AppError.configuration("Unknown model: \(model)")
        }
        // Allow configured overrides not in the default catalog (data-driven).
        return model
    }
}
