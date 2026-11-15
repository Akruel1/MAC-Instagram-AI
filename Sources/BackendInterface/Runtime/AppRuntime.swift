import Foundation
import Core
import Persistence
import AI
import MCP
import Instagram
import Video
import Dependencies
import Hermes
import Jobs

public final class AppRuntime: @unchecked Sendable {
    public let configuration: AppConfiguration
    public let container: ServiceContainer
    public let logger: Logger
    public let database: DatabaseManager
    public let keychain: KeychainStore
    public let approvalBroker: any ApprovalBroker
    public let jobCoordinator: JobCoordinator
    public let dependencyManager: DependencyManager
    public let hermesManager: HermesManager
    public let mcpRegistry: MCPRegistry
    public let permissionGate: ToolPermissionGate
    public let conversations: ConversationRepository
    public let audit: AuditLogRepository
    public let preferences: AppPreferencesRepository
    public let instagramRepository: InstagramRepository
    public let analyticsEngine: AnalyticsEngine
    public let oauth: InstagramOAuthService
    public let ffmpegEngine: FFmpegEngine
    public private(set) var orchestrator: AIOrchestrator?
    public private(set) var features: FeatureAvailability
    public private(set) var initErrors: [String] = []

    private let eventContinuations = UnfairLockBox<[UUID: AsyncStream<BackendEvent>.Continuation]>([:])
    private let httpClient: HTTPClient

    public init(
        configuration: AppConfiguration = AppConfiguration(),
        keychain: KeychainStore? = nil,
        approvalBroker: (any ApprovalBroker)? = nil,
        logger: Logger = StructuredLogger(),
        http: HTTPClient = URLSessionHTTPClient(),
        claudeClient: (any ClaudeAPIClient)? = nil
    ) throws {
        try configuration.validate()
        try FileManager.default.createDirectory(at: configuration.applicationSupportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configuration.mediaDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configuration.tempDirectoryURL, withIntermediateDirectories: true)

        self.configuration = configuration
        self.logger = logger
        self.container = ServiceContainer()
        self.keychain = keychain ?? KeychainSecretsStore(service: configuration.keychainService)
        self.approvalBroker = approvalBroker ?? DenyByDefaultApprovalBroker()

        do {
            self.database = try DatabaseManager(databaseURL: configuration.databaseURL)
        } catch {
            throw AppError.persistence("Database init failed: \(error.localizedDescription)")
        }

        self.httpClient = http
        self.conversations = ConversationRepository(db: database)
        self.audit = AuditLogRepository(db: database)
        self.preferences = AppPreferencesRepository(db: database)
        self.instagramRepository = InstagramRepository(db: database)
        self.analyticsEngine = AnalyticsEngine(repository: instagramRepository)
        let jobRepo = JobRepository(db: database)
        self.jobCoordinator = JobCoordinator(repository: jobRepo, audit: audit, logger: logger)
        self.dependencyManager = DependencyManager(
            stateRepository: InstallationStateRepository(db: database),
            approvalBroker: self.approvalBroker
        )
        self.hermesManager = HermesManager(
            dependencyManager: dependencyManager,
            keychain: self.keychain,
            approvalBroker: self.approvalBroker
        )
        self.mcpRegistry = MCPRegistry(repository: MCPRegistryRepository(db: database))
        let roots = [configuration.mediaDirectoryURL, configuration.tempDirectoryURL, configuration.applicationSupportDirectory]
        self.permissionGate = ToolPermissionGate(
            policy: ToolPermissionPolicy(allowedRoots: roots),
            approvalBroker: self.approvalBroker
        )
        self.oauth = InstagramOAuthService(configuration: configuration, keychain: self.keychain, http: http)
        self.ffmpegEngine = FFmpegEngine()

        let profile = dependencyManager.detectSystem()
        var features = FeatureAvailability()
        features.nodeAvailable = profile.dependencies.first(where: { $0.id == "node" })?.available == true
        features.pythonAvailable = profile.dependencies.first(where: { $0.id == "python" })?.available == true
        features.ffmpegAvailable = profile.dependencies.first(where: { $0.id == "ffmpeg" })?.available == true
        features.hermesAvailable = profile.dependencies.first(where: { $0.id == "hermes" })?.available == true
        features.claudeConfigured = (try? self.keychain.hasSecret(account: KeychainAccount.anthropicAPIKey)) ?? false
        features.instagramAuthenticated = (try? self.keychain.hasSecret(account: KeychainAccount.instagramAccessToken)) ?? false
        self.features = features

        let videoHandler = VideoJobHandler(
            engine: ffmpegEngine,
            allowedRoot: configuration.applicationSupportDirectory,
            approvalBroker: self.approvalBroker
        )
        Task {
            await jobCoordinator.register(videoHandler)
            try? await jobCoordinator.recoverIncomplete()
        }

        let client: any ClaudeAPIClient
        if let claudeClient {
            client = claudeClient
        } else {
            client = ClaudeClient(configuration: configuration, keychain: self.keychain, http: http)
        }

        let analyticsProvider: @Sendable (Int) async throws -> GroundedAnalyticsPayload = { [analyticsEngine, oauth] days in
            guard let tokenSet = try await oauth.storedToken(), !tokenSet.isExpired else {
                return GroundedAnalyticsPayload(
                    report: nil,
                    source: "keychain",
                    note: "NOT LIVE VERIFIED — credentials unavailable or expired"
                )
            }
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            // Prefer persisted metrics; do not fabricate. Live Graph sync is a separate explicit step.
            let report = try? analyticsEngine.buildReport(
                accountId: tokenSet.userID ?? "unknown",
                periodStart: start,
                periodEnd: end,
                expectedMetrics: ["reach", "views", "likes", "comments", "saves", "shares"]
            )
            return GroundedAnalyticsPayload(
                report: report,
                source: "sqlite+keychain",
                note: report == nil || (report?.observedMetrics.isEmpty ?? true)
                    ? "NOT LIVE VERIFIED — no persisted metrics; live Graph sync required"
                    : "Observed metrics from local store"
            )
        }

        self.orchestrator = AIOrchestrator(
            client: client,
            conversations: conversations,
            audit: audit,
            permissionGate: permissionGate,
            configuration: configuration,
            analyticsProvider: analyticsProvider,
            videoPlanner: { request in
                // Typed plan stub: LLM cannot pass raw ffmpeg args.
                _ = request
                return VideoEditPlan(operations: [], requiresApproval: true)
            }
        )

        container.registerSingleton(AppConfiguration.self, instance: configuration)
        container.registerSingleton(KeychainStore.self, instance: self.keychain)
        logger.info("AppRuntime initialized", metadata: [
            "ffmpeg": String(features.ffmpegAvailable),
            "claude": String(features.claudeConfigured)
        ])
    }

    public func events() -> AsyncStream<BackendEvent> {
        AsyncStream { continuation in
            let id = UUID()
            self.eventContinuations.withLock { $0[id] = continuation }
            continuation.onTermination = { [eventContinuations] _ in
                eventContinuations.withLock { $0[id] = nil }
            }
        }
    }

    public func publish(_ event: BackendEvent) {
        let conts = eventContinuations.withLock { Array($0.values) }
        for c in conts { c.yield(event) }
    }

    public func onboardingStatus() -> OnboardingStatusDTO {
        var incomplete: [String] = []
        if !features.claudeConfigured { incomplete.append("configure_claude_api_key") }
        if !features.instagramAuthenticated { incomplete.append("instagram_oauth") }
        if !features.ffmpegAvailable { incomplete.append("install_ffmpeg") }
        let completed = (try? preferences.getBool(AppPreferenceKey.onboardingCompleted)) ?? false
        return OnboardingStatusDTO(
            claudeConfigured: features.claudeConfigured,
            instagramAuthenticated: features.instagramAuthenticated,
            dependenciesReady: features.ffmpegAvailable,
            hermesOptionalReady: features.hermesAvailable,
            onboardingCompleted: completed,
            incompleteSteps: incomplete
        )
    }

    public func diagnostics() -> DiagnosticsDTO {
        DiagnosticsDTO(
            features: features,
            system: dependencyManager.detectSystem(),
            hermes: hermesManager.status(),
            databasePath: configuration.databaseURL.path
        )
    }

    public func setClaudeAPIKey(_ key: String) throws {
        try keychain.setSecret(key, account: KeychainAccount.anthropicAPIKey)
        features.claudeConfigured = true
        publish(.featureAvailability(features))
    }

    public func clearClaudeAPIKey() throws {
        try keychain.deleteSecret(account: KeychainAccount.anthropicAPIKey)
        features.claudeConfigured = false
        publish(.featureAvailability(features))
    }

    public func clearInstagramCredentials() async throws {
        try await oauth.clearTokens()
        features.instagramAuthenticated = false
        publish(.featureAvailability(features))
    }

    public func setOnboardingCompleted(_ value: Bool) throws {
        try preferences.setBool(AppPreferenceKey.onboardingCompleted, value)
    }

    public func markInstagramAuthenticated(_ value: Bool = true) {
        features.instagramAuthenticated = value
        publish(.featureAvailability(features))
    }

    public func linkedInstagramAccount() async -> LinkedInstagramAccountDTO {
        do {
            guard let token = try await oauth.storedToken() else {
                return LinkedInstagramAccountDTO(
                    userID: nil,
                    authenticated: false,
                    tokenExpired: false,
                    note: "No Instagram credentials in Keychain"
                )
            }
            return LinkedInstagramAccountDTO(
                userID: token.userID,
                authenticated: true,
                tokenExpired: token.isExpired,
                note: token.isExpired
                    ? "Token present but expired — reconnect required"
                    : "Credentials present in Keychain (live Graph not verified on this call)"
            )
        } catch {
            return LinkedInstagramAccountDTO(
                userID: nil,
                authenticated: false,
                tokenExpired: false,
                note: "Keychain read failed: \(error.localizedDescription)"
            )
        }
    }

    public func syncInstagramAnalytics(days: Int = 7) async -> AnalyticsSyncResultDTO {
        do {
            guard let token = try await oauth.storedToken(), !token.isExpired else {
                return AnalyticsSyncResultDTO(
                    success: false,
                    accountId: nil,
                    persistedCount: 0,
                    note: "NOT LIVE VERIFIED — credentials unavailable or expired; Graph sync skipped"
                )
            }
            let accountId = token.userID ?? "me"
            let oauth = self.oauth
            let client = InstagramGraphClient(
                configuration: configuration,
                http: httpClient,
                tokenProvider: {
                    guard let t = try await oauth.storedToken()?.accessToken else {
                        throw AppError.authentication("Instagram token missing")
                    }
                    return t
                }
            )
            let me: InstagramAccountDTO
            if token.userID == nil {
                me = try await client.fetchMe()
            } else {
                me = InstagramAccountDTO(id: accountId, username: accountId)
            }
            let insights = try await client.fetchAccountInsights(
                userID: me.id,
                metrics: ["reach", "views", "likes", "comments", "saves", "shares"],
                period: "day"
            )
            let observed = try analyticsEngine.persistInsights(
                accountId: me.id,
                mediaId: nil,
                insights: insights,
                provenance: "instagram.graph.live"
            )
            publish(.diagnostic("Analytics sync persisted \(observed.count) metrics for \(me.id)"))
            return AnalyticsSyncResultDTO(
                success: true,
                accountId: me.id,
                persistedCount: observed.count,
                note: "Live Graph sync completed — verify metrics completeness in Analytics"
            )
        } catch {
            return AnalyticsSyncResultDTO(
                success: false,
                accountId: nil,
                persistedCount: 0,
                note: "Graph sync failed: \(error.localizedDescription)"
            )
        }
    }

    public func chatMessages(conversationId: String) throws -> [ChatMessageDTO] {
        try conversations.messages(conversationId: conversationId).map { message in
            let text: String
            if let data = message.contentJSON.data(using: .utf8),
               let blocks = try? JSONDecoder().decode([ClaudeContentBlock].self, from: data) {
                text = blocks.compactMap {
                    if case .text(let t) = $0 { return t }
                    return nil
                }.joined()
            } else {
                text = message.contentJSON
            }
            return ChatMessageDTO(
                id: message.id,
                conversationId: message.conversationId,
                role: message.role,
                text: text,
                createdAt: message.createdAt
            )
        }
    }

    public func recentJobs(limit: Int = 12) async throws -> [RecentJobDTO] {
        let jobs = try await jobCoordinator.recent(limit: limit)
        return jobs.map {
            RecentJobDTO(
                id: $0.id,
                kind: $0.kind,
                state: $0.state.rawValue,
                progress: $0.progress,
                errorMessage: $0.errorMessage,
                updatedAt: $0.updatedAt
            )
        }
    }

    public func inspectMedia(path: String) async throws -> MediaInspection {
        try await ffmpegEngine.inspect(path: path)
    }

    public func refreshFeatureFlags() {
        let profile = dependencyManager.detectSystem()
        features.nodeAvailable = profile.dependencies.first(where: { $0.id == "node" })?.available == true
        features.pythonAvailable = profile.dependencies.first(where: { $0.id == "python" })?.available == true
        features.ffmpegAvailable = profile.dependencies.first(where: { $0.id == "ffmpeg" })?.available == true
        features.hermesAvailable = profile.dependencies.first(where: { $0.id == "hermes" })?.available == true
        features.claudeConfigured = (try? keychain.hasSecret(account: KeychainAccount.anthropicAPIKey)) ?? false
        features.instagramAuthenticated = (try? keychain.hasSecret(account: KeychainAccount.instagramAccessToken)) ?? false
        publish(.featureAvailability(features))
    }

    public func chat(conversationId: String?, text: String, model: String? = nil) async throws -> OrchestratorResult {
        guard let orchestrator else {
            throw AppError.configuration("Orchestrator unavailable")
        }
        let result = try await orchestrator.handleUserMessage(conversationId: conversationId, text: text, model: model)
        publish(.chatDelta(conversationId: result.conversationId, text: result.assistantText))
        return result
    }

    public func shutdown() async {
        logger.info("AppRuntime shutting down")
        let conts = eventContinuations.withLock { state -> [AsyncStream<BackendEvent>.Continuation] in
            let values = Array(state.values)
            state.removeAll()
            return values
        }
        for c in conts { c.finish() }
    }
}
