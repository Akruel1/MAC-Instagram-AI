import SwiftUI
import AppKit
import AppUI
import BackendInterface
import Core
import DesignSystem

final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct InstagramAIStudioApp: App {
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var appDelegate
    @State private var model: AppModel?
    @State private var bootError: String?
    @AppStorage("ui.appearance") private var appearanceRaw = "system"

    var body: some Scene {
        WindowGroup("Instagram AI Studio") {
            Group {
                if let model {
                    RootView(model: model)
                } else if let bootError {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Failed to start").font(StudioType.title)
                        Text(bootError).font(StudioType.body).foregroundStyle(.secondary)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .studioPaletteEnvironment()
                } else {
                    ProgressView("Starting Instagram AI Studio…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .studioPaletteEnvironment()
                        .task { await bootstrap() }
                }
            }
            .preferredColorScheme(preferredScheme)
            .frame(minWidth: StudioSpace.windowMinWidth, minHeight: StudioSpace.windowMinHeight)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Button("Overview") { model?.select(.overview) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Analytics") { model?.select(.analytics) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Studio") { model?.select(.studio) }
                    .keyboardShortcut("3", modifiers: .command)
                    // FeaturePolicy blocks Studio; shortcut still routes through select(_:).
                Button("Assistant") { model?.select(.assistant) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Integrations") { model?.select(.integrations) }
                    .keyboardShortcut("5", modifiers: .command)
            }
            CommandMenu("Studio") {
                Button("Command Palette…") { model?.commandPalettePresented = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Refresh") {
                    Task { await model?.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            if let model {
                SettingsView(model: model)
                    .preferredColorScheme(preferredScheme)
            } else {
                ProgressView()
                    .frame(width: 420, height: 200)
            }
        }
    }

    @MainActor
    private func bootstrap() async {
        do {
            let runtime = try await Task.detached(priority: .userInitiated) {
                try AppRuntime(approvalBroker: UIApprovalBroker())
            }.value
            model = AppModel(runtime: runtime)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            do {
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("InstagramAIStudio-Fallback", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let runtime = try AppRuntime(
                    configuration: AppConfiguration(applicationSupportDirectory: dir),
                    keychain: InMemoryKeychainStore(),
                    approvalBroker: UIApprovalBroker()
                )
                let fallback = AppModel(runtime: runtime)
                fallback.lastError = "Runtime init issue: \(error.localizedDescription)"
                model = fallback
            } catch {
                bootError = error.localizedDescription
            }
        }
    }

    private var preferredScheme: ColorScheme? {
        switch appearanceRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
