import SwiftUI
import DesignSystem
import BackendInterface

public struct OverviewView: View {
    @Bindable var model: AppModel
    @Environment(\.studioPalette) private var palette

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        ContentColumn(maxWidth: 820) {
            workspaceHeader
            setupFocus
                .padding(.bottom, StudioSpace.xl)
            activitySection
                .padding(.bottom, StudioSpace.xl)
            focusActions
                .padding(.bottom, StudioSpace.lg)
            Divider().overlay(palette.border).padding(.bottom, StudioSpace.md)
            toolsFooter
        }
        .background(palette.bgBase)
        .task { await model.refreshAll() }
    }

    private var workspaceHeader: some View {
        WorkspaceHeader(
            title: "Overview",
            status: model.readiness.label,
            statusColor: readinessColor
        ) {
            HStack(spacing: 8) {
                Button {
                    model.diagnosticsPresented = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Diagnostics")

                if model.isRefreshing || model.isLoadingOverview {
                    ProgressView().controlSize(.small).frame(width: 28, height: 28)
                } else {
                    Button {
                        Task { await model.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }

                StudioToolbarButton(
                    model.primaryAction.title,
                    systemImage: model.primaryAction.systemImage,
                    isPrimary: true
                ) {
                    model.performPrimaryAction()
                }
            }
        }
    }

    private var readinessColor: Color {
        switch model.readiness {
        case .ready: return palette.success
        case .limited: return palette.warning
        case .needsSetup: return palette.accent
        }
    }

    private var setupFocus: some View {
        VStack(alignment: .leading, spacing: StudioSpace.sm) {
            StudioSectionLabel("Accounts")
            VStack(spacing: 0) {
                accountRow(
                    title: "Claude",
                    subtitle: model.features.claudeConfigured ? "Ready for Assistant" : "Optional — required only for chat",
                    connected: model.features.claudeConfigured,
                    isPrimaryFocus: model.primaryAction == .connectClaude,
                    actionTitle: model.features.claudeConfigured ? nil : "Connect",
                    action: { model.claudeSetupPresented = true }
                )
                Rectangle().fill(palette.border).frame(height: 0.5).padding(.leading, 28)
                accountRow(
                    title: "Instagram",
                    subtitle: model.instagramConnected
                        ? (model.linkedAccount.userID.map { "Account \($0)" } ?? "Connected")
                        : "Optional — required for live Analytics sync",
                    connected: model.instagramConnected,
                    isPrimaryFocus: model.primaryAction == .connectInstagram,
                    actionTitle: model.instagramConnected ? nil : "Connect",
                    action: { Task { await model.beginInstagramConnect() } }
                )
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(palette.bgElevated))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 0.5))
        }
    }

    private func accountRow(
        title: String,
        subtitle: String,
        connected: Bool,
        isPrimaryFocus: Bool,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(connected ? palette.success : (isPrimaryFocus ? palette.accent : palette.textTertiary))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    Text(connected ? "Connected" : "Not connected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(connected ? palette.success : palette.textTertiary)
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: isPrimaryFocus ? .semibold : .medium))
                    .foregroundStyle(isPrimaryFocus ? palette.accent : palette.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isPrimaryFocus && !connected ? palette.accentMuted.opacity(0.35) : Color.clear)
    }

    @ViewBuilder
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: StudioSpace.sm) {
            HStack {
                StudioSectionLabel("Recent activity")
                Spacer()
                if !model.recentJobs.isEmpty {
                    Text("\(model.recentJobs.count)")
                        .font(StudioType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            if model.recentJobs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No exports yet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Export and sync jobs appear here with live progress when available.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: 440, alignment: .leading)
                }
                .padding(.vertical, StudioSpace.md)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(palette.border).frame(height: 0.5)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.recentJobs.enumerated()), id: \.element.id) { index, job in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(job.kind)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Text(job.state.capitalized)
                                    .font(StudioType.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                            StudioProgressBar(progress: job.progress)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        if index < model.recentJobs.count - 1 {
                            Rectangle().fill(palette.border).frame(height: 0.5)
                        }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 0.5))
            }
        }
    }

    private var focusActions: some View {
        VStack(alignment: .leading, spacing: StudioSpace.sm) {
            StudioSectionLabel("Continue")
            HStack(spacing: 8) {
                StudioToolbarButton("Assistant", systemImage: "text.bubble", isPrimary: true) {
                    model.select(.assistant)
                }
                StudioToolbarButton("Analytics", systemImage: "chart.xyaxis.line") {
                    model.select(.analytics)
                }
                StudioToolbarButton("Integrations", systemImage: "puzzlepiece.extension") {
                    model.select(.integrations)
                }
            }
            Text("Studio is coming in a future version. FFmpeg status remains available in Integrations.")
                .font(StudioType.caption)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var toolsFooter: some View {
        HStack(spacing: StudioSpace.md) {
            Text("Local tools")
                .font(StudioType.caption)
                .foregroundStyle(palette.textTertiary)
            StudioInlineStatus("FFmpeg", ok: model.features.ffmpegAvailable)
            StudioInlineStatus("Node", ok: model.features.nodeAvailable)
            StudioInlineStatus("Python", ok: model.features.pythonAvailable)
            Spacer()
            Button("Integrations") { model.select(.integrations) }
                .buttonStyle(.plain)
                .font(StudioType.caption)
                .foregroundStyle(palette.textTertiary)
        }
    }
}
