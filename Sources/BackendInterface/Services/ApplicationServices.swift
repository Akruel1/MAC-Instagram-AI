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

/// Stable facade for Phase 2 SwiftUI. UI must consume these APIs, not parse CLI output.
public struct ApplicationServices: Sendable {
    private let runtime: AppRuntime

    public init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    public var approvalBroker: any ApprovalBroker {
        runtime.approvalBroker
    }

    public func onboardingStatus() -> OnboardingStatusDTO {
        runtime.onboardingStatus()
    }

    public func setOnboardingCompleted(_ value: Bool) throws {
        try runtime.setOnboardingCompleted(value)
    }

    public func diagnostics() -> DiagnosticsDTO {
        runtime.diagnostics()
    }

    public func events() -> AsyncStream<BackendEvent> {
        runtime.events()
    }

    public func jobEvents() -> AsyncStream<JobProgressEvent> {
        // JobCoordinator is an actor; expose a stream that bridges into BackendEvent publishing as well.
        AsyncStream { continuation in
            let task = Task {
                let stream = await runtime.jobCoordinator.progressStream()
                for await event in stream {
                    runtime.publish(.jobProgress(event))
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func configureClaude(apiKey: String) throws {
        try runtime.setClaudeAPIKey(apiKey)
    }

    public func clearClaudeAPIKey() throws {
        try runtime.clearClaudeAPIKey()
    }

    public func beginInstagramOAuth() async throws -> URL {
        let (url, _) = try await runtime.oauth.beginAuthorization()
        return url
    }

    public func completeInstagramOAuth(callbackURL: URL) async throws {
        _ = try await runtime.oauth.completeAuthorization(callbackURL: callbackURL)
        runtime.markInstagramAuthenticated(true)
    }

    public func clearInstagramCredentials() async throws {
        try await runtime.clearInstagramCredentials()
    }

    public func linkedInstagramAccount() async -> LinkedInstagramAccountDTO {
        await runtime.linkedInstagramAccount()
    }

    public func dependencyPlan() -> InstallationPlan {
        runtime.dependencyManager.planInstallation()
    }

    public func executeDependencyPlan(_ plan: InstallationPlan) async throws {
        try await runtime.dependencyManager.execute(plan: plan, approved: false)
    }

    public func sendChat(conversationId: String?, text: String, model: String? = nil) async throws -> OrchestratorResult {
        try await runtime.chat(conversationId: conversationId, text: text, model: model)
    }

    public func listConversations() throws -> [ConversationRecord] {
        try runtime.conversations.listConversations()
    }

    public func chatMessages(conversationId: String) throws -> [ChatMessageDTO] {
        try runtime.chatMessages(conversationId: conversationId)
    }

    public func hermesStatus() -> HermesStatus {
        runtime.hermesManager.status()
    }

    public func submitVideoPlan(_ plan: VideoEditPlan) async throws -> JobRecord {
        let data = try JSONEncoder().encode(plan)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let job = try await runtime.jobCoordinator.submit(kind: "video.render", payloadJSON: json)
        try await runtime.jobCoordinator.enqueue(job.id)
        return job
    }

    public func jobStatus(_ id: String) async throws -> JobRecord {
        try await runtime.jobCoordinator.status(id)
    }

    public func cancelJob(_ id: String) async throws {
        try await runtime.jobCoordinator.cancel(id)
    }

    public func recentJobs(limit: Int = 12) async throws -> [RecentJobDTO] {
        try await runtime.recentJobs(limit: limit)
    }

    public func inspectMedia(path: String) async throws -> MediaInspection {
        try await runtime.inspectMedia(path: path)
    }

    public func mcpReviewedIntegrations() -> [MCPIntegrationDescriptor] {
        runtime.mcpRegistry.reviewedIntegrations
    }

    public func analyticsReport(accountId: String, days: Int) throws -> AnalyticsReport {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        return try runtime.analyticsEngine.buildReport(
            accountId: accountId,
            periodStart: start,
            periodEnd: end,
            expectedMetrics: ["reach", "views", "likes", "comments", "saves", "shares"]
        )
    }

    public func syncInstagramAnalytics(days: Int = 7) async -> AnalyticsSyncResultDTO {
        await runtime.syncInstagramAnalytics(days: days)
    }

    public func resolveApproval(id: UUID, decision: ApprovalDecision) async {
        if let ui = runtime.approvalBroker as? UIApprovalBroker {
            await ui.resolve(id: id, decision: decision)
        }
    }

    public func pendingApprovals() async -> AsyncStream<UIApprovalBroker.PendingApproval?> {
        if let ui = runtime.approvalBroker as? UIApprovalBroker {
            return await ui.pendingApprovals()
        }
        return AsyncStream { $0.finish() }
    }

    public func refreshFeatures() {
        runtime.refreshFeatureFlags()
    }

    public var mediaDirectoryURL: URL {
        runtime.configuration.mediaDirectoryURL
    }

    public var applicationSupportDirectory: URL {
        runtime.configuration.applicationSupportDirectory
    }

    /// Copies an external file into the managed Media directory (required for typed FFmpeg paths).
    public func importMedia(from sourceURL: URL) throws -> URL {
        // Legacy sync helper retained for callers that only need a copy; prefer `importAndInspectMedia`.
        let mediaRoot = runtime.configuration.mediaDirectoryURL
        try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
        let dest = mediaRoot.appendingPathComponent("\(UUID().uuidString).\(ext)")
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return dest
    }

    public func importAndInspectMedia(from sourceURL: URL) async throws -> MediaImportResult {
        let service = MediaImportService(
            mediaRoot: runtime.configuration.mediaDirectoryURL,
            engine: runtime.ffmpegEngine
        )
        return try await service.importAndInspect(from: sourceURL)
    }

    public func setMCPEnabled(id: String, enabled: Bool) throws {
        try runtime.mcpRegistry.persistEnabled(id, enabled: enabled)
    }

    public func displayName() -> String {
        let stored = (try? runtime.preferences.getString(AppPreferenceKey.displayName)) ?? ""
        return DisplayNamePolicy.sanitize(stored) ?? DisplayNamePolicy.fallback
    }

    public func hasConfiguredDisplayName() -> Bool {
        guard let raw = try? runtime.preferences.getString(AppPreferenceKey.displayName) else { return false }
        return DisplayNamePolicy.sanitize(raw) != nil
    }

    public func setDisplayName(_ raw: String) throws {
        guard let sanitized = DisplayNamePolicy.sanitize(raw) else {
            throw AppError.validation("Enter a name with at least one character.")
        }
        try runtime.preferences.setString(AppPreferenceKey.displayName, sanitized)
        try runtime.preferences.setBool(AppPreferenceKey.displayNamePromptCompleted, true)
    }

    public func needsDisplayNamePrompt() -> Bool {
        let onboardingDone = (try? runtime.preferences.getBool(AppPreferenceKey.onboardingCompleted)) ?? false
        let promptDone = (try? runtime.preferences.getBool(AppPreferenceKey.displayNamePromptCompleted)) ?? false
        return onboardingDone && !hasConfiguredDisplayName() && !promptDone
    }

    public func markDisplayNamePromptCompleted() throws {
        try runtime.preferences.setBool(AppPreferenceKey.displayNamePromptCompleted, true)
    }
}
