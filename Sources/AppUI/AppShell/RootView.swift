import SwiftUI
import DesignSystem
import Core

public struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 188, ideal: 208, max: 248)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StudioPalette(scheme: colorScheme).bgBase)
        }
        .navigationSplitViewStyle(.balanced)
        .studioPaletteEnvironment()
        .background(StudioPalette(scheme: colorScheme).bgBase)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.commandPalettePresented = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Command Palette (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
            }
        }
        .navigationTitle(model.selectedWorkspace.title)
        .sheet(isPresented: $model.commandPalettePresented) {
            CommandPaletteView(model: model)
        }
        .sheet(isPresented: $model.diagnosticsPresented) {
            DiagnosticsSheet(model: model)
        }
        .sheet(isPresented: $model.claudeSetupPresented) {
            ClaudeSetupSheet(model: model)
        }
        .sheet(isPresented: $model.donatePresented) {
            DonateSheet()
        }
        .sheet(isPresented: $model.showDisplayNamePrompt) {
            DisplayNamePrompt(model: model)
        }
        .sheet(item: $model.pendingApproval) { pending in
            ApprovalSheet(pending: pending) { decision in
                model.resolveApproval(decision)
            }
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(model: model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .alert(
            model.lastError == FeaturePolicy.studioComingSoonMessage ? "Studio" : "Notice",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .frame(minWidth: StudioSpace.windowMinWidth, minHeight: StudioSpace.windowMinHeight)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedWorkspace {
        case .overview:
            OverviewView(model: model)
        case .analytics:
            AnalyticsView(model: model)
        case .studio:
            // Studio implementation retained for future versions; navigation is gated by FeaturePolicy.
            ComingSoonWorkspaceView(title: "Studio", message: FeaturePolicy.studioComingSoonMessage)
        case .assistant:
            AssistantView(model: model)
        case .integrations:
            IntegrationsView(model: model)
        }
    }
}

private struct ComingSoonWorkspaceView: View {
    let title: String
    let message: String
    @Environment(\.studioPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: 420, alignment: .leading)
        }
        .padding(StudioSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgBase)
    }
}

private struct DiagnosticsSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.studioPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Diagnostics")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            labeled("Database", model.diagnostics.databasePath)
            labeled("macOS", model.diagnostics.system.macOSVersion)
            labeled("Architecture", model.diagnostics.system.architecture)
            labeled(
                "Hermes",
                model.diagnostics.hermes.installed
                    ? (model.diagnostics.hermes.version ?? "Installed")
                    : "Not installed"
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("Tools")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                ForEach(model.diagnostics.system.dependencies, id: \.id) { dep in
                    HStack {
                        Text(dep.displayName).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(dep.available ? (dep.path ?? "Available") : "Missing")
                            .font(StudioType.mono)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 520, height: 380)
        .background(palette.bgElevated)
        .studioPaletteEnvironment()
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(StudioType.mono)
                .foregroundStyle(palette.textSecondary)
                .textSelection(.enabled)
        }
    }
}

private struct ClaudeSetupSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.studioPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect Claude")
                .font(.system(size: 16, weight: .semibold))
            Text("Your API key is stored in the macOS Keychain on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
            SecureField("Anthropic API key", text: $model.claudeAPIKeyDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { model.saveClaudeAPIKey() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(palette.bgElevated)
        .studioPaletteEnvironment()
    }
}

private struct ApprovalSheet: View {
    let pending: UIApprovalBroker.PendingApproval
    let onResolve: (ApprovalDecision) -> Void
    @Environment(\.studioPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Approval required")
                .font(.system(size: 16, weight: .semibold))
            Text(pending.request.summary)
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
            Text("\(pending.request.category) · \(pending.request.action)")
                .font(StudioType.caption)
                .foregroundStyle(palette.textTertiary)
            HStack {
                Spacer()
                Button("Deny") {
                    onResolve(.denied)
                    dismiss()
                }
                Button("Approve") {
                    onResolve(.approved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(palette.bgElevated)
        .studioPaletteEnvironment()
    }
}
