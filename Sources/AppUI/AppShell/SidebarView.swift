import SwiftUI
import DesignSystem
import Core

struct SidebarView: View {
    @Bindable var model: AppModel
    @Environment(\.studioPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.top, 18)
                .padding(.bottom, 18)

            Text("LIBRARY")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            VStack(spacing: 1) {
                ForEach(AppModel.Workspace.allCases) { workspace in
                    StudioSidebarItem(
                        title: workspace.title,
                        systemImage: workspace.systemImage,
                        isSelected: model.selectedWorkspace == workspace,
                        isEnabled: workspace.isEnabled,
                        disabledBadge: workspace == .studio ? "Coming soon" : "Unavailable"
                    ) {
                        model.select(workspace)
                    }
                    .help(workspace.isEnabled ? workspace.title : FeaturePolicy.studioComingSoonMessage)
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                DonateButton {
                    model.donatePresented = true
                }
                .padding(.horizontal, 12)

                footer
            }
        }
        .padding(.bottom, 12)
        .background(palette.bgSidebar)
    }

    private var brand: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(palette.accent)
                .frame(width: 18, height: 18)
                .overlay(
                    Text("A")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.08))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("Instagram AI Studio")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(model.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .accessibilityLabel("Display name \(model.displayName)")
            }
        }
        .padding(.horizontal, 14)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(palette.border).frame(height: 0.5).padding(.horizontal, 10)
            VStack(alignment: .leading, spacing: 5) {
                footerLine("Claude", model.features.claudeConfigured ? "Connected" : "Optional")
                footerLine("Instagram", model.instagramConnected ? "Connected" : "Optional")
                footerLine("FFmpeg", model.features.ffmpegAvailable ? "Ready" : "Missing")
            }
            .padding(.horizontal, 14)
        }
    }

    private func footerLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
        }
    }
}
