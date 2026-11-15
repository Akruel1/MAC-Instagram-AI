import Foundation
import BackendInterface
import Core
import Dependencies

@main
struct InstagramAIStudioCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "help"

        do {
            let support = FileManager.default.temporaryDirectory
                .appendingPathComponent("InstagramAIStudio-CLI-\(UUID().uuidString)", isDirectory: true)
            var config = AppConfiguration(applicationSupportDirectory: support)
            if let model = ProcessInfo.processInfo.environment["CLAUDE_MODEL"] {
                config.claudeDefaultModel = model
            }
            let broker: any ApprovalBroker = args.contains("--yes")
                ? DenyByDefaultApprovalBroker(allowAll: true)
                : CLIApprovalBroker()
            let runtime = try AppRuntime(
                configuration: config,
                keychain: InMemoryKeychainStore(),
                approvalBroker: broker
            )
            // For CLI harness, prefer Keychain when available; seed from env for development.
            if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
                try runtime.setClaudeAPIKey(key)
            }
            let services = ApplicationServices(runtime: runtime)
            try await run(command: command, args: Array(args.dropFirst()), services: services, runtime: runtime)
            await runtime.shutdown()
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run(
        command: String,
        args: [String],
        services: ApplicationServices,
        runtime: AppRuntime
    ) async throws {
        switch command {
        case "help", "--help", "-h":
            print("""
            Instagram AI Studio — Phase 1 backend CLI

            Usage:
              instagram-ai-studio <command> [--yes]

            Commands:
              help                 Show this help
              doctor               Print diagnostics and feature availability
              onboarding           Show onboarding status
              deps plan            Show dependency installation plan
              deps install         Execute dependency plan (requires approval unless --yes)
              chat <message>       Send a chat message through the AI orchestrator
              hermes status        Show optional Hermes status
              mcp list             List reviewed MCP integrations
              version              Print version
            """)
        case "version":
            print("instagram-ai-studio 0.1.0-phase1")
        case "doctor":
            let d = services.diagnostics()
            print("Database: \(d.databasePath)")
            print("macOS: \(d.system.macOSVersion)")
            print("Arch: \(d.system.architecture)")
            for dep in d.system.dependencies {
                print("- \(dep.id): \(dep.available ? "OK" : "MISSING") \(dep.version ?? "") \(dep.path ?? "")")
            }
            print("Hermes installed: \(d.hermes.installed)")
            print("Features: claude=\(d.features.claudeConfigured) ig=\(d.features.instagramAuthenticated) ffmpeg=\(d.features.ffmpegAvailable)")
        case "onboarding":
            let status = services.onboardingStatus()
            print("Claude: \(status.claudeConfigured)")
            print("Instagram: \(status.instagramAuthenticated)")
            print("Deps ready: \(status.dependenciesReady)")
            print("Incomplete: \(status.incompleteSteps.joined(separator: ", "))")
        case "deps":
            let sub = args.first ?? "plan"
            if sub == "plan" {
                let plan = services.dependencyPlan()
                print(plan.summary)
                for step in plan.steps {
                    print("- [\(step.id)] \(step.title): \(step.command) \(step.arguments.joined(separator: " "))")
                }
            } else if sub == "install" {
                let plan = services.dependencyPlan()
                try await services.executeDependencyPlan(plan)
                print("Installation plan execution finished")
            } else {
                throw AppError.validation("Unknown deps subcommand")
            }
        case "chat":
            let message = args.joined(separator: " ")
            guard !message.isEmpty else { throw AppError.validation("chat requires a message") }
            let result = try await services.sendChat(conversationId: nil, text: message)
            print("conversation: \(result.conversationId)")
            print(result.assistantText)
            if !result.missingData.isEmpty {
                print("missing_data: \(result.missingData.joined(separator: ", "))")
            }
        case "hermes":
            let status = services.hermesStatus()
            print("installed=\(status.installed) path=\(status.path ?? "-") telegram=\(status.telegramConfigured)")
            for note in status.notes { print("note: \(note)") }
        case "mcp":
            for item in services.mcpReviewedIntegrations() {
                print("- \(item.id) v\(item.version): \(item.displayName)")
            }
        default:
            throw AppError.validation("Unknown command: \(command)")
        }
    }
}
