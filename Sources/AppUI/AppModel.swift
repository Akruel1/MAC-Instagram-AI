import Foundation
import AppKit
import UniformTypeIdentifiers
import Observation
import Core
import BackendInterface
import Persistence
import Jobs
import Dependencies
import Hermes
import Instagram
import Video
import AI
import MCP

@MainActor
@Observable
public final class AppModel {
    public enum Workspace: String, CaseIterable, Identifiable, Sendable {
        case overview
        case analytics
        case studio
        case assistant
        case integrations

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .overview: return "Overview"
            case .analytics: return "Analytics"
            case .studio: return "Studio"
            case .assistant: return "Assistant"
            case .integrations: return "Integrations"
            }
        }

        public var systemImage: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .analytics: return "chart.xyaxis.line"
            case .studio: return "slider.horizontal.2.square"
            case .assistant: return "text.bubble"
            case .integrations: return "puzzlepiece.extension"
            }
        }

        public var isEnabled: Bool {
            FeaturePolicy.isWorkspaceEnabled(rawValue)
        }
    }

    public enum Readiness: String, Sendable {
        case needsSetup
        case ready
        case limited

        public var label: String {
            switch self {
            case .needsSetup: return "Setup needed"
            case .ready: return "Ready"
            case .limited: return "Limited"
            }
        }
    }

    public enum PrimaryAction: Equatable, Sendable {
        case connectClaude
        case connectInstagram
        case installFFmpeg
        case openStudio
        case refresh

        public var title: String {
            switch self {
            case .connectClaude: return "Connect Claude"
            case .connectInstagram: return "Connect Instagram"
            case .installFFmpeg: return "Check tools"
            case .openStudio: return "Open Studio"
            case .refresh: return "Refresh"
            }
        }

        public var systemImage: String {
            switch self {
            case .connectClaude: return "key.fill"
            case .connectInstagram: return "link"
            case .installFFmpeg: return "hammer"
            case .openStudio: return "slider.horizontal.2.square"
            case .refresh: return "arrow.clockwise"
            }
        }
    }

    public private(set) var services: ApplicationServices
    public private(set) var runtime: AppRuntime
    public var selectedWorkspace: Workspace = .overview
    public var features: FeatureAvailability = FeatureAvailability()
    public var onboarding: OnboardingStatusDTO
    public var diagnostics: DiagnosticsDTO
    public var linkedAccount: LinkedInstagramAccountDTO
    public var recentJobs: [RecentJobDTO] = []
    public var lastError: String?
    public var isLoadingOverview = false
    public var isRefreshing = false
    public var commandPalettePresented = false
    public var diagnosticsPresented = false
    public var claudeSetupPresented = false
    public var claudeAPIKeyDraft = ""
    public var showOnboarding: Bool
    public var showDisplayNamePrompt = false
    public var donatePresented = false
    public var displayName: String
    public var displayNameDraft = ""
    public var pendingApproval: UIApprovalBroker.PendingApproval?

    // Analytics
    public var analyticsDays: Int = 7
    public var analyticsReport: AnalyticsReport?
    public var analyticsNote: String?
    public var analyticsLoading = false

    // Assistant
    public var conversations: [ConversationRecord] = []
    public var selectedConversationId: String?
    public var chatMessages: [ChatMessageDTO] = []
    public var chatDraft = ""
    public var chatBusy = false

    // Studio
    public var studioMediaURL: URL?
    public var studioInspection: MediaInspection?
    public var studioInPoint: Double = 0
    public var studioOutPoint: Double = 0
    public var studioExportPreset: StudioExportPreset = .reels1080x1920
    public var studioJob: RecentJobDTO?
    public var studioBusy = false

    // Integrations
    public var mcpIntegrations: [MCPIntegrationDescriptor] = []
    public var dependencyPlan: InstallationPlan?
    public var hermesStatus: HermesStatus?

    public enum StudioExportPreset: String, CaseIterable, Identifiable, Sendable {
        case reels1080x1920
        case square1080
        case landscape1920x1080

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .reels1080x1920: return "Reels 1080×1920"
            case .square1080: return "Square 1080×1080"
            case .landscape1920x1080: return "Landscape 1920×1080"
            }
        }

        public var size: (Int, Int) {
            switch self {
            case .reels1080x1920: return (1080, 1920)
            case .square1080: return (1080, 1080)
            case .landscape1920x1080: return (1920, 1080)
            }
        }
    }

    private var eventTask: Task<Void, Never>?
    private var jobTask: Task<Void, Never>?
    private var approvalTask: Task<Void, Never>?

    public init(runtime: AppRuntime) {
        let services = ApplicationServices(runtime: runtime)
        self.runtime = runtime
        self.services = services
        self.features = runtime.features
        self.onboarding = services.onboardingStatus()
        self.showOnboarding = !services.onboardingStatus().onboardingCompleted
        self.displayName = services.displayName()
        self.displayNameDraft = services.hasConfiguredDisplayName() ? services.displayName() : ""
        self.showDisplayNamePrompt = services.needsDisplayNamePrompt()
        self.diagnostics = DiagnosticsDTO(
            features: runtime.features,
            system: SystemProfile(
                macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: {
                    #if arch(arm64)
                    return "arm64"
                    #else
                    return "x86_64"
                    #endif
                }(),
                dependencies: []
            ),
            hermes: HermesStatus(
                installed: runtime.features.hermesAvailable,
                notes: ["Status loads asynchronously after first paint"]
            ),
            databasePath: runtime.configuration.databaseURL.path
        )
        self.linkedAccount = LinkedInstagramAccountDTO(
            userID: nil,
            authenticated: runtime.features.instagramAuthenticated,
            tokenExpired: false,
            note: runtime.features.instagramAuthenticated ? "Connected" : "Not connected"
        )
        self.mcpIntegrations = services.mcpReviewedIntegrations()
    }

    public var readiness: Readiness {
        if !features.claudeConfigured && !features.instagramAuthenticated && !features.ffmpegAvailable {
            return .needsSetup
        }
        if features.ffmpegAvailable && (features.claudeConfigured || features.instagramAuthenticated) {
            return features.ffmpegAvailable && features.claudeConfigured && features.instagramAuthenticated
                ? .ready
                : .limited
        }
        if features.ffmpegAvailable { return .limited }
        return .needsSetup
    }

    public var primaryAction: PrimaryAction {
        if !features.claudeConfigured { return .connectClaude }
        if !features.instagramAuthenticated || linkedAccount.tokenExpired { return .connectInstagram }
        if !features.ffmpegAvailable { return .installFFmpeg }
        if FeaturePolicy.studioWorkspaceEnabled {
            return .openStudio
        }
        return .refresh
    }

    public var instagramConnected: Bool {
        linkedAccount.authenticated && !linkedAccount.tokenExpired
    }

    public func start() {
        services.refreshFeatures()
        Task { await refreshSnapshot() }
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.services.events() {
                await MainActor.run { self.handle(event) }
            }
        }
        jobTask?.cancel()
        jobTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.services.jobEvents() {
                await MainActor.run {
                    if let current = self.studioJob, current.id == event.jobId {
                        self.studioJob = RecentJobDTO(
                            id: event.jobId,
                            kind: current.kind,
                            state: event.state.rawValue,
                            progress: event.progress,
                            errorMessage: event.message,
                            updatedAt: Date()
                        )
                    }
                }
                await self.reloadJobs()
            }
        }
        approvalTask?.cancel()
        approvalTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.services.pendingApprovals()
            for await pending in stream {
                await MainActor.run { self.pendingApproval = pending }
            }
        }
        Task { await reloadJobs() }
        Task { await loadIntegrations() }
        if selectedWorkspace == .studio, !FeaturePolicy.studioWorkspaceEnabled {
            selectedWorkspace = .overview
        }
    }

    public func stop() {
        eventTask?.cancel()
        jobTask?.cancel()
        approvalTask?.cancel()
    }

    public func select(_ workspace: Workspace) {
        guard workspace.isEnabled else {
            if workspace == .studio {
                lastError = FeaturePolicy.studioComingSoonMessage
            } else {
                lastError = "\(workspace.title) is unavailable."
            }
            return
        }
        selectedWorkspace = workspace
        switch workspace {
        case .analytics:
            Task { await loadAnalytics() }
        case .assistant:
            Task { await loadConversations() }
        case .integrations:
            Task { await loadIntegrations() }
        case .overview:
            Task { await refreshAll() }
        case .studio:
            break
        }
    }

    public func performPrimaryAction() {
        switch primaryAction {
        case .connectClaude:
            claudeSetupPresented = true
        case .connectInstagram:
            Task { await beginInstagramConnect() }
        case .installFFmpeg:
            diagnosticsPresented = true
        case .openStudio:
            select(.studio)
        case .refresh:
            Task { await refreshAll() }
        }
    }

    public func saveDisplayNameFromDraft() {
        do {
            try services.setDisplayName(displayNameDraft)
            displayName = services.displayName()
            displayNameDraft = displayName
            showDisplayNamePrompt = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func skipDisplayNamePrompt() {
        do {
            try services.markDisplayNamePromptCompleted()
            showDisplayNamePrompt = false
            displayName = services.displayName()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await refreshSnapshot()
        await reloadJobs()
    }

    public func refreshSnapshot() async {
        features = runtime.features
        onboarding = services.onboardingStatus()
        showOnboarding = !onboarding.onboardingCompleted
        displayName = services.displayName()
        if !showOnboarding {
            showDisplayNamePrompt = services.needsDisplayNamePrompt()
        }
        let services = self.services
        diagnostics = await Task.detached(priority: .utility) {
            services.diagnostics()
        }.value
        linkedAccount = await services.linkedInstagramAccount()
        hermesStatus = services.hermesStatus()
    }

    public func reloadJobs() async {
        isLoadingOverview = true
        defer { isLoadingOverview = false }
        do {
            recentJobs = try await services.recentJobs(limit: 8)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func completeOnboarding() {
        do {
            if DisplayNamePolicy.sanitize(displayNameDraft) != nil {
                try services.setDisplayName(displayNameDraft)
                displayName = services.displayName()
            }
            try services.setOnboardingCompleted(true)
            showOnboarding = false
            onboarding = services.onboardingStatus()
            showDisplayNamePrompt = services.needsDisplayNamePrompt()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func saveClaudeAPIKey() {
        let key = claudeAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            lastError = "Enter a Claude API key."
            return
        }
        do {
            try services.configureClaude(apiKey: key)
            claudeAPIKeyDraft = ""
            claudeSetupPresented = false
            Task { await refreshSnapshot() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func clearClaude() {
        do {
            try services.clearClaudeAPIKey()
            Task { await refreshSnapshot() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func clearInstagram() {
        Task {
            do {
                try await services.clearInstagramCredentials()
                await refreshSnapshot()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    public func beginInstagramConnect() async {
        do {
            let url = try await services.beginInstagramOAuth()
            NSWorkspace.shared.open(url)
        } catch {
            lastError = "Instagram sign-in isn’t configured yet. Add Meta app credentials, then try again."
        }
    }

    public func resolveApproval(_ decision: ApprovalDecision) {
        guard let pending = pendingApproval else { return }
        Task {
            await services.resolveApproval(id: pending.id, decision: decision)
        }
    }

    // MARK: Analytics

    public func loadAnalytics() async {
        analyticsLoading = true
        defer { analyticsLoading = false }
        await refreshSnapshot()
        guard instagramConnected, let accountId = linkedAccount.userID ?? (linkedAccount.authenticated ? "unknown" : nil) else {
            analyticsReport = nil
            analyticsNote = "Connect Instagram to load observed metrics. Nothing is fabricated."
            return
        }
        do {
            let report = try services.analyticsReport(accountId: accountId == "unknown" ? (linkedAccount.userID ?? "me") : accountId, days: analyticsDays)
            analyticsReport = report
            if report.observedMetrics.isEmpty {
                analyticsNote = "No persisted metrics yet. Use Sync to pull live Graph data when credentials allow."
            } else {
                analyticsNote = report.missingMetrics.isEmpty
                    ? "Showing observed metrics from local store."
                    : "Missing metrics: \(report.missingMetrics.joined(separator: ", "))"
            }
        } catch {
            analyticsReport = nil
            analyticsNote = error.localizedDescription
        }
    }

    public func syncAnalytics() async {
        analyticsLoading = true
        defer { analyticsLoading = false }
        let result = await services.syncInstagramAnalytics(days: analyticsDays)
        analyticsNote = result.note
        if result.success, let accountId = result.accountId {
            linkedAccount = await services.linkedInstagramAccount()
            analyticsReport = try? services.analyticsReport(accountId: accountId, days: analyticsDays)
        }
    }

    // MARK: Assistant

    public func loadConversations() async {
        do {
            conversations = try services.listConversations()
            if selectedConversationId == nil {
                selectedConversationId = conversations.first?.id
            }
            if let id = selectedConversationId {
                chatMessages = try services.chatMessages(conversationId: id)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func sendChat() async {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard features.claudeConfigured else {
            lastError = "Connect Claude before chatting. No replies are fabricated."
            return
        }
        chatBusy = true
        defer { chatBusy = false }
        do {
            let result = try await services.sendChat(conversationId: selectedConversationId, text: text)
            chatDraft = ""
            selectedConversationId = result.conversationId
            await loadConversations()
            chatMessages = try services.chatMessages(conversationId: result.conversationId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Studio

    public func importStudioMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        // Retain security-scoped access across the async import hop.
        let gotAccess = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if gotAccess { url.stopAccessingSecurityScopedResource() }
            }
            await loadImportedMedia(url)
        }
    }

    public func loadImportedMedia(_ url: URL) async {
        studioBusy = true
        defer { studioBusy = false }
        do {
            // Copy + ffprobe off the critical UI path; only publish state after success.
            let result = try await Task.detached(priority: .userInitiated) { [services] in
                try await services.importAndInspectMedia(from: url)
            }.value
            studioMediaURL = result.managedURL
            studioInspection = result.inspection
            let duration = max(0, result.inspection.durationSeconds ?? 0)
            studioInPoint = 0
            studioOutPoint = duration
            studioJob = nil
        } catch {
            studioMediaURL = nil
            studioInspection = nil
            studioInPoint = 0
            studioOutPoint = 0
            lastError = error.localizedDescription
        }
    }

    public func exportStudioClip() async {
        guard features.ffmpegAvailable else {
            lastError = "FFmpeg is required for Studio exports."
            return
        }
        guard let media = studioMediaURL else {
            lastError = "Import a clip first."
            return
        }
        let duration = max(0.1, studioOutPoint - studioInPoint)
        let root = services.applicationSupportDirectory
        let outName = "export-\(UUID().uuidString).mp4"
        let trimmed = root.appendingPathComponent("Temp").appendingPathComponent("trim-\(UUID().uuidString).mp4")
        let exported = root.appendingPathComponent("Media").appendingPathComponent(outName)
        try? FileManager.default.createDirectory(at: trimmed.deletingLastPathComponent(), withIntermediateDirectories: true)
        let size = studioExportPreset.size
        let plan = VideoEditPlan(
            operations: [
                .trim(input: media.path, output: trimmed.path, startSeconds: studioInPoint, durationSeconds: duration),
                .exportVertical(
                    input: trimmed.path,
                    output: exported.path,
                    width: size.0,
                    height: size.1,
                    videoBitrate: "4M"
                )
            ],
            requiresApproval: true
        )
        studioBusy = true
        defer { studioBusy = false }
        do {
            let job = try await services.submitVideoPlan(plan)
            studioJob = RecentJobDTO(
                id: job.id,
                kind: job.kind,
                state: job.state.rawValue,
                progress: job.progress,
                errorMessage: job.errorMessage,
                updatedAt: job.updatedAt
            )
            await reloadJobs()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func cancelStudioJob() async {
        guard let id = studioJob?.id else { return }
        do {
            try await services.cancelJob(id)
            await reloadJobs()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Integrations

    public func loadIntegrations() async {
        mcpIntegrations = services.mcpReviewedIntegrations()
        dependencyPlan = services.dependencyPlan()
        hermesStatus = services.hermesStatus()
        await refreshSnapshot()
    }

    public func runDependencyPlan() async {
        guard let plan = dependencyPlan else { return }
        do {
            try await services.executeDependencyPlan(plan)
            await loadIntegrations()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func toggleMCP(id: String, enabled: Bool) {
        do {
            try services.setMCPEnabled(id: id, enabled: enabled)
            Task { await loadIntegrations() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handle(_ event: BackendEvent) {
        switch event {
        case .featureAvailability(let features):
            self.features = features
            Task { await refreshSnapshot() }
        case .jobProgress:
            Task { await reloadJobs() }
        case .chatDelta(let conversationId, _):
            if conversationId == selectedConversationId {
                Task { await loadConversations() }
            }
        case .toolApproval, .diagnostic, .log:
            break
        }
    }
}
