import SwiftUI
import DesignSystem
import Persistence

public struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("ui.appearance") private var appearanceRaw = "system"
    @Environment(\.studioPalette) private var palette

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("Profile") {
                TextField("Display name", text: $model.displayNameDraft)
                    .onChange(of: model.displayNameDraft) { _, value in
                        if value.count > DisplayNamePolicy.maxLength {
                            model.displayNameDraft = String(value.prefix(DisplayNamePolicy.maxLength))
                        }
                    }
                HStack {
                    Text("Shown under Instagram AI Studio in the sidebar.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") { model.saveDisplayNameFromDraft() }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearanceRaw) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Claude") {
                HStack {
                    Text(model.features.claudeConfigured ? "API key in Keychain" : "Not configured")
                    Spacer()
                    if model.features.claudeConfigured {
                        Button("Remove") { model.clearClaude() }
                    } else {
                        Button("Add key…") { model.claudeSetupPresented = true }
                    }
                }
            }

            Section("Instagram") {
                HStack {
                    Text(model.instagramConnected ? "Connected" : "Not connected")
                    Spacer()
                    if model.instagramConnected {
                        Button("Disconnect") { model.clearInstagram() }
                    } else {
                        Button("Connect…") { Task { await model.beginInstagramConnect() } }
                    }
                }
            }

            Section("Diagnostics") {
                LabeledContent("Database") {
                    Text(model.diagnostics.databasePath)
                        .font(StudioType.mono)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                LabeledContent("Architecture") {
                    Text(model.diagnostics.system.architecture)
                }
                LabeledContent("FFmpeg") {
                    Text(model.features.ffmpegAvailable ? "Detected" : "Missing")
                }
                Button("Open diagnostics…") { model.diagnosticsPresented = true }
            }

            Section("Support") {
                Button("Donate…") { model.donatePresented = true }
                Text("Optional. Never required to use the app.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("Secrets stay in Keychain. Your display name and metrics stay on this Mac unless you sync Instagram or call Claude.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("Onboarding") {
                Button("Show setup guide again") {
                    try? model.services.setOnboardingCompleted(false)
                    model.showOnboarding = true
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(minWidth: 460, minHeight: 480)
        .studioPaletteEnvironment()
    }
}
