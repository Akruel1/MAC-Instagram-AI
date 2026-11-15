import SwiftUI
import DesignSystem
import Persistence
import Core

struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.studioPalette) private var palette
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                brand
                Spacer()
                Button("Skip for now") {
                    model.completeOnboarding()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.textTertiary)
            }
            .padding(24)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: 480, alignment: .leading)

                stepBody
            }
            .padding(.horizontal, 48)

            Spacer()

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                StudioToolbarButton(primaryTitle, isPrimary: true, isEnabled: canAdvance) {
                    advance()
                }
            }
            .padding(32)
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(palette.bgBase)
        .studioPaletteEnvironment()
    }

    private var brand: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(palette.accent)
                .frame(width: 18, height: 18)
            Text("Instagram AI Studio")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
        }
    }

    private var title: String {
        switch step {
        case 0: return "What should we call you?"
        case 1: return "Local creative control"
        case 2: return "Connect what you need"
        default: return "You’re ready to work"
        }
    }

    private var subtitle: String {
        switch step {
        case 0:
            return "A friendly name for the sidebar. It stays on this Mac only — no account signup required."
        case 1:
            return "Ground analytics in observed Instagram data and use Claude only when configured. Studio video editing arrives in a future version."
        case 2:
            return "Connect accounts when you want Assistant or live metrics. Everything else works locally."
        default:
            return "Open Overview anytime. Finish remaining setup from Settings or Integrations."
        }
    }

    private var canAdvance: Bool {
        if step == 0 {
            return DisplayNamePolicy.sanitize(model.displayNameDraft) != nil
        }
        return true
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 10) {
                TextField("Your name", text: $model.displayNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onChange(of: model.displayNameDraft) { _, value in
                        if value.count > DisplayNamePolicy.maxLength {
                            model.displayNameDraft = String(value.prefix(DisplayNamePolicy.maxLength))
                        }
                    }
                Text("You can change this later in Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textTertiary)
            }
        case 1:
            VStack(alignment: .leading, spacing: 10) {
                bullet("Keychain for secrets, SQLite for local state")
                bullet("Honest empty states when data isn’t available")
                bullet("Studio is marked Coming soon — FFmpeg diagnostics stay available")
            }
        case 2:
            VStack(alignment: .leading, spacing: 12) {
                statusRow("FFmpeg", ok: model.features.ffmpegAvailable, detail: model.features.ffmpegAvailable ? "Detected locally" : "Optional tooling via Integrations")
                statusRow("Claude", ok: model.features.claudeConfigured, detail: model.features.claudeConfigured ? "Connected" : "Optional for Assistant") {
                    model.claudeSetupPresented = true
                }
                statusRow("Instagram", ok: model.instagramConnected, detail: model.instagramConnected ? "Connected" : "Optional for Analytics") {
                    Task { await model.beginInstagramConnect() }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested next step")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("Explore Overview, Assistant, Analytics, or Integrations.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var primaryTitle: String {
        step < 3 ? "Continue" : "Get started"
    }

    private func advance() {
        if step == 0 {
            model.saveDisplayNameFromDraft()
            guard model.services.hasConfiguredDisplayName() else { return }
        }
        if step < 3 {
            step += 1
        } else {
            model.completeOnboarding()
            model.select(.overview)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(palette.accent).frame(width: 5, height: 5).padding(.top, 6)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func statusRow(_ title: String, ok: Bool, detail: String, action: (() -> Void)? = nil) -> some View {
        HStack {
            Circle().fill(ok ? palette.success : palette.textTertiary).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text(detail).font(.system(size: 12)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            if let action, !ok {
                Button("Connect", action: action)
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.accent)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 0.5))
    }
}
