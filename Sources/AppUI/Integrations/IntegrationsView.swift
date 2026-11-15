import SwiftUI
import DesignSystem
import Dependencies
import MCP

struct IntegrationsView: View {
    @Bindable var model: AppModel
    @Environment(\.studioPalette) private var palette

    var body: some View {
        ContentColumn(maxWidth: 860) {
            WorkspaceHeader(
                title: "Integrations",
                status: model.features.ffmpegAvailable ? "Local tools detected" : "FFmpeg missing",
                statusColor: model.features.ffmpegAvailable ? palette.success : palette.warning
            ) {
                StudioToolbarButton("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.loadIntegrations() }
                }
            }

            VStack(alignment: .leading, spacing: StudioSpace.xl) {
                toolsSection
                dependenciesSection
                mcpSection
                hermesSection
            }
        }
        .background(palette.bgBase)
        .task { await model.loadIntegrations() }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: StudioSpace.sm) {
            StudioSectionLabel("Local tools")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                toolCard("FFmpeg", ok: model.features.ffmpegAvailable, note: "Required for Studio")
                toolCard("Node", ok: model.features.nodeAvailable, note: "Optional MCP / fixtures")
                toolCard("Python", ok: model.features.pythonAvailable, note: "Optional tooling")
                toolCard("ffprobe", ok: model.diagnostics.system.dependencies.first(where: { $0.id == "ffprobe" })?.available == true, note: "Media inspection")
            }
        }
    }

    private func toolCard(_ title: String, ok: Bool, note: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(ok ? palette.success : palette.textTertiary).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text(note).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(ok ? "Ready" : "Missing")
                .font(StudioType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(palette.bgElevated))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 0.5))
    }

    private var dependenciesSection: some View {
        VStack(alignment: .leading, spacing: StudioSpace.sm) {
            StudioSectionLabel("Installation plan")
            if let plan = model.dependencyPlan, !plan.steps.isEmpty {
                Text(plan.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                ForEach(plan.steps, id: \.id) { step in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.textPrimary)
                            Text(step.rationale).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                        }
                        Spacer()
                        Text(step.packageManager)
                            .font(StudioType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.vertical, 6)
                }
                StudioToolbarButton("Run plan…", systemImage: "hammer", isPrimary: true) {
                    Task { await model.runDependencyPlan() }
                }
                Text("Execution requires explicit approval.")
                    .font(StudioType.caption)
                    .foregroundStyle(palette.textTertiary)
            } else {
                Text("No installation steps required right now.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: StudioSpace.sm) {
            StudioSectionLabel("Reviewed MCP")
            if model.mcpIntegrations.isEmpty {
                Text("No reviewed MCP integrations registered.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(model.mcpIntegrations, id: \.id) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                            Text("\(item.installationMethod) · \(item.version)")
                                .font(StudioType.caption)
                                .foregroundStyle(palette.textTertiary)
                            Text(item.requiredDependencies.isEmpty ? "No extra deps" : "Needs \(item.requiredDependencies.joined(separator: ", "))")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textTertiary)
                        }
                        Spacer()
                        Toggle("Enable", isOn: Binding(
                            get: { false },
                            set: { model.toggleMCP(id: item.id, enabled: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 0.5))
                }
            }
        }
    }

    private var hermesSection: some View {
        VStack(alignment: .leading, spacing: StudioSpace.sm) {
            StudioSectionLabel("Hermes (optional)")
            let installed = model.hermesStatus?.installed == true
            Text(installed
                 ? "Hermes binary detected. Tool bridge remains disabled in this app build."
                 : "Hermes is optional and not installed. The app works without it.")
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: 520, alignment: .leading)
        }
    }
}
