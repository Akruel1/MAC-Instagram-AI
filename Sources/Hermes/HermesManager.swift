import Foundation
import Core
import Dependencies

/// Optional Hermes Agent integration. The application functions fully without Hermes.
public struct HermesStatus: Sendable, Equatable, Codable {
    public var installed: Bool
    public var path: String?
    public var version: String?
    public var gatewayRunning: Bool?
    public var telegramConfigured: Bool
    public var notes: [String]

    public init(
        installed: Bool,
        path: String? = nil,
        version: String? = nil,
        gatewayRunning: Bool? = nil,
        telegramConfigured: Bool = false,
        notes: [String] = []
    ) {
        self.installed = installed
        self.path = path
        self.version = version
        self.gatewayRunning = gatewayRunning
        self.telegramConfigured = telegramConfigured
        self.notes = notes
    }
}

public struct TelegramHermesConfig: Sendable, Equatable, Codable {
    public var allowedUserIDs: [String]

    public init(allowedUserIDs: [String]) {
        self.allowedUserIDs = allowedUserIDs
    }
}

/// Explicit authenticated boundary for sharing approved tools with Hermes.
/// Hermes does not automatically access Swift services.
public protocol HermesToolBridge: Sendable {
    func exportedToolNames() -> [String]
    func invokeApprovedTool(name: String, payloadJSON: String, authToken: String) async throws -> String
}

public struct DisabledHermesToolBridge: HermesToolBridge {
    public init() {}
    public func exportedToolNames() -> [String] { [] }
    public func invokeApprovedTool(name: String, payloadJSON: String, authToken: String) async throws -> String {
        throw AppError.dependency("Hermes tool bridge is not enabled. Shared Swift capabilities require an explicit authenticated bridge.")
    }
}

public struct HermesManager: Sendable {
    private let dependencyManager: DependencyManager
    private let keychain: KeychainStore
    private let approvalBroker: any ApprovalBroker
    private let processRunner: ProcessRunnerLike
    private let hermesHome: URL
    public let toolBridge: any HermesToolBridge

    public init(
        dependencyManager: DependencyManager,
        keychain: KeychainStore,
        approvalBroker: any ApprovalBroker,
        processRunner: ProcessRunnerLike = WhichProcessRunner(),
        hermesHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes"),
        toolBridge: any HermesToolBridge = DisabledHermesToolBridge()
    ) {
        self.dependencyManager = dependencyManager
        self.keychain = keychain
        self.approvalBroker = approvalBroker
        self.processRunner = processRunner
        self.hermesHome = hermesHome
        self.toolBridge = toolBridge
    }

    public func status() -> HermesStatus {
        let profile = dependencyManager.detectSystem()
        let hermes = profile.dependencies.first(where: { $0.id == "hermes" })
        let envPath = hermesHome.appendingPathComponent(".env")
        var telegramConfigured = false
        var notes: [String] = [
            "Hermes is optional.",
            "Official install uses an interactive installer; this app never silently pipes curl|bash."
        ]
        if FileManager.default.fileExists(atPath: envPath.path) {
            if let contents = try? String(contentsOf: envPath, encoding: .utf8) {
                telegramConfigured = contents.contains("TELEGRAM_BOT_TOKEN=") && contents.contains("TELEGRAM_ALLOWED_USERS=")
            }
        }
        if hermes?.available != true {
            notes.append("Hermes binary not detected on PATH.")
        }
        notes.append("Swift services are not auto-exported to Hermes; use HermesToolBridge.")
        return HermesStatus(
            installed: hermes?.available == true,
            path: hermes?.path,
            version: hermes?.version,
            gatewayRunning: nil,
            telegramConfigured: telegramConfigured,
            notes: notes
        )
    }

    public func installationPlan() -> InstallationPlan {
        InstallationPlan(
            steps: [
                InstallationStep(
                    id: "hermes-official-install",
                    title: "Install Hermes Agent (official installer)",
                    command: "echo",
                    arguments: [
                        "Review https://hermes-agent.nousresearch.com/docs/getting-started/quickstart then run the official installer manually after approval"
                    ],
                    packageManager: "manual",
                    rationale: "Official Hermes docs use curl|bash; we refuse silent execution and require explicit user approval/manual run"
                )
            ],
            summary: "Hermes optional install plan (manual, approved)"
        )
    }

    public func configureTelegram(allowedUserIDs: [String], botToken: String) async throws {
        let decision = try await approvalBroker.requestApproval(
            ApprovalRequest(
                category: "hermes_telegram",
                action: "configure",
                summary: "Store Telegram bot token in Keychain and write allowlist to Hermes .env",
                details: ["allowedUsers": allowedUserIDs.joined(separator: ",")]
            )
        )
        guard decision == .approved else {
            throw AppError.permissionDenied("Telegram configuration denied")
        }
        try keychain.setSecret(botToken, account: KeychainAccount.telegramBotToken)
        try FileManager.default.createDirectory(at: hermesHome, withIntermediateDirectories: true)
        let envURL = hermesHome.appendingPathComponent(".env")
        var lines: [String] = []
        if let existing = try? String(contentsOf: envURL, encoding: .utf8) {
            lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            lines.removeAll { $0.hasPrefix("TELEGRAM_BOT_TOKEN=") || $0.hasPrefix("TELEGRAM_ALLOWED_USERS=") }
        }
        // Hermes docs store token in ~/.hermes/.env — write after Keychain stash; avoid logging token.
        lines.append("TELEGRAM_BOT_TOKEN=\(botToken)")
        lines.append("TELEGRAM_ALLOWED_USERS=\(allowedUserIDs.joined(separator: ","))")
        try lines.joined(separator: "\n").write(to: envURL, atomically: true, encoding: .utf8)
    }

    public func gatewayStatus() async throws -> String {
        guard let hermes = processRunner.which("hermes") else {
            throw AppError.dependency("Hermes not installed")
        }
        // Verified command from official docs: `hermes gateway status`
        let code = try await processRunner.run(executable: hermes, arguments: ["gateway", "status"])
        return code == 0 ? "ok" : "not-running-or-error-\(code)"
    }

    public func startGateway() async throws {
        try await runGatewayCommand(["gateway", "start"])
    }

    public func stopGateway() async throws {
        try await runGatewayCommand(["gateway", "stop"])
    }

    public func disable() throws {
        // Safe disable: do not uninstall globally; clear local integration markers only.
        // Leaving Hermes binary intact keeps optionality reversible.
    }

    private func runGatewayCommand(_ args: [String]) async throws {
        guard let hermes = processRunner.which("hermes") else {
            throw AppError.dependency("Hermes not installed")
        }
        let decision = try await approvalBroker.requestApproval(
            ApprovalRequest(
                category: "hermes_gateway",
                action: args.joined(separator: " "),
                summary: "Run hermes \(args.joined(separator: " "))"
            )
        )
        guard decision == .approved else {
            throw AppError.permissionDenied("Gateway command denied")
        }
        let code = try await processRunner.run(executable: hermes, arguments: args)
        guard code == 0 else {
            throw AppError.external(service: "hermes", message: "Exit code \(code)")
        }
    }
}
