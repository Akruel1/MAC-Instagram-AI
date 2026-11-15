import Foundation
import Core
import Persistence

public struct DetectedDependency: Sendable, Equatable, Codable {
    public var id: String
    public var displayName: String
    public var available: Bool
    public var version: String?
    public var path: String?
    public var notes: String?

    public init(id: String, displayName: String, available: Bool, version: String? = nil, path: String? = nil, notes: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.available = available
        self.version = version
        self.path = path
        self.notes = notes
    }
}

public struct InstallationStep: Sendable, Equatable, Codable {
    public var id: String
    public var title: String
    public var command: String
    public var arguments: [String]
    public var requiresAdmin: Bool
    public var packageManager: String
    public var rationale: String

    public init(
        id: String,
        title: String,
        command: String,
        arguments: [String],
        requiresAdmin: Bool = false,
        packageManager: String,
        rationale: String
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.arguments = arguments
        self.requiresAdmin = requiresAdmin
        self.packageManager = packageManager
        self.rationale = rationale
    }
}

public struct InstallationPlan: Sendable, Equatable, Codable {
    public var id: String
    public var createdAt: Date
    public var steps: [InstallationStep]
    public var summary: String

    public init(id: String = UUID().uuidString, createdAt: Date = Date(), steps: [InstallationStep], summary: String) {
        self.id = id
        self.createdAt = createdAt
        self.steps = steps
        self.summary = summary
    }
}

public struct SystemProfile: Sendable, Equatable, Codable {
    public var macOSVersion: String
    public var architecture: String
    public var dependencies: [DetectedDependency]

    public init(macOSVersion: String, architecture: String, dependencies: [DetectedDependency]) {
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.dependencies = dependencies
    }
}

public struct DependencyManager: Sendable {
    private let processRunner: ProcessRunnerLike
    private let stateRepository: InstallationStateRepository?
    private let approvalBroker: any ApprovalBroker
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        processRunner: ProcessRunnerLike = WhichProcessRunner(),
        stateRepository: InstallationStateRepository? = nil,
        approvalBroker: any ApprovalBroker,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.processRunner = processRunner
        self.stateRepository = stateRepository
        self.approvalBroker = approvalBroker
        self.isExecutable = isExecutable
    }

    public func detectSystem() -> SystemProfile {
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let deps = [
            detectExecutable(id: "node", displayName: "Node.js", names: ["node"]),
            detectExecutable(id: "python", displayName: "Python", names: ["python3", "python"]),
            detectExecutable(
                id: "ffmpeg",
                displayName: "FFmpeg",
                names: ["ffmpeg"],
                knownPaths: [
                    "/opt/local/bin/ffmpeg",
                    "/opt/homebrew/bin/ffmpeg",
                    "/usr/local/bin/ffmpeg",
                    "/usr/bin/ffmpeg"
                ]
            ),
            detectExecutable(
                id: "ffprobe",
                displayName: "FFprobe",
                names: ["ffprobe"],
                knownPaths: [
                    "/opt/local/bin/ffprobe",
                    "/opt/homebrew/bin/ffprobe",
                    "/usr/local/bin/ffprobe",
                    "/usr/bin/ffprobe"
                ]
            ),
            detectExecutable(id: "hermes", displayName: "Hermes Agent", names: ["hermes"]),
            detectExecutable(id: "brew", displayName: "Homebrew", names: ["brew"]),
            detectExecutable(
                id: "port",
                displayName: "MacPorts",
                names: ["port"],
                knownPaths: ["/opt/local/bin/port"]
            )
        ]
        return SystemProfile(macOSVersion: version, architecture: arch, dependencies: deps)
    }

    public func planInstallation(forMissingFrom profile: SystemProfile? = nil) -> InstallationPlan {
        let profile = profile ?? detectSystem()
        var steps: [InstallationStep] = []
        let brew = profile.dependencies.first(where: { $0.id == "brew" })?.available == true
        let port = profile.dependencies.first(where: { $0.id == "port" })?.available == true
            || isExecutable("/opt/local/bin/port")

        if profile.dependencies.first(where: { $0.id == "ffmpeg" })?.available != true {
            if brew {
                steps.append(
                    InstallationStep(
                        id: "install-ffmpeg",
                        title: "Install FFmpeg via Homebrew",
                        command: "brew",
                        arguments: ["install", "ffmpeg"],
                        packageManager: "homebrew",
                        rationale: "Required for local video processing"
                    )
                )
            } else if port {
                steps.append(
                    InstallationStep(
                        id: "install-ffmpeg-macports",
                        title: "Install FFmpeg via MacPorts",
                        command: "/opt/local/bin/port",
                        arguments: ["install", "ffmpeg"],
                        requiresAdmin: true,
                        packageManager: "macports",
                        rationale: "Required for local video processing; MacPorts typically needs privileges"
                    )
                )
            } else {
                steps.append(
                    InstallationStep(
                        id: "install-ffmpeg-manual",
                        title: "Install FFmpeg via a supported package manager",
                        command: "echo",
                        arguments: [
                            "Install FFmpeg with MacPorts (`sudo port install ffmpeg`) or Homebrew (`brew install ffmpeg`). Refusing silent curl|bash."
                        ],
                        packageManager: "manual",
                        rationale: "No supported package manager detected for automatic install"
                    )
                )
            }
        }
        if profile.dependencies.first(where: { $0.id == "node" })?.available != true && brew {
            steps.append(
                InstallationStep(
                    id: "install-node",
                    title: "Install Node.js via Homebrew",
                    command: "brew",
                    arguments: ["install", "node"],
                    packageManager: "homebrew",
                    rationale: "Required for optional Remotion/MCP fixtures"
                )
            )
        }
        return InstallationPlan(
            steps: steps,
            summary: steps.isEmpty ? "All required dependencies detected" : "\(steps.count) installation step(s) planned"
        )
    }

    public func execute(plan: InstallationPlan, approved: Bool) async throws {
        if !approved {
            let decision = try await approvalBroker.requestApproval(
                ApprovalRequest(
                    category: "dependency_install",
                    action: "execute_plan",
                    summary: plan.summary,
                    details: ["steps": plan.steps.map(\.id).joined(separator: ",")]
                )
            )
            guard decision == .approved else {
                throw AppError.permissionDenied("Installation plan denied")
            }
        }
        for step in plan.steps {
            if step.packageManager == "manual" {
                throw AppError.dependency("Manual step required: \(step.rationale). Not auto-executed.")
            }
            if step.requiresAdmin {
                throw AppError.authorization("Admin privileges required for \(step.id); not executed without elevated approval workflow")
            }
            try PathSafety.assertNoShellMetacharacters(step.command, label: "install.command")
            for arg in step.arguments {
                try PathSafety.assertNoShellMetacharacters(arg, label: "install.arg")
            }
            // Idempotent: re-detect before install
            let current = detectSystem()
            if step.id.contains("ffmpeg"), current.dependencies.first(where: { $0.id == "ffmpeg" })?.available == true {
                try stateRepository?.upsert(InstallationStateRecord(dependencyId: "ffmpeg", status: "installed", version: current.dependencies.first { $0.id == "ffmpeg" }?.version, path: current.dependencies.first { $0.id == "ffmpeg" }?.path))
                continue
            }
            let result = try await processRunner.run(executable: step.command, arguments: step.arguments)
            guard result == 0 else {
                throw AppError.dependency("Installation step \(step.id) failed with exit \(result)")
            }
            try stateRepository?.upsert(InstallationStateRecord(dependencyId: step.id, status: "installed", updatedAt: Date()))
        }
    }

    private func detectExecutable(
        id: String,
        displayName: String,
        names: [String],
        knownPaths: [String] = []
    ) -> DetectedDependency {
        for path in knownPaths where isExecutable(path) {
            let version = processRunner.version(path: path)
            return DetectedDependency(
                id: id,
                displayName: displayName,
                available: true,
                version: version,
                path: path,
                notes: path.hasPrefix("/opt/local/") ? "Discovered via MacPorts path" : nil
            )
        }
        for name in names {
            if let path = processRunner.which(name) {
                let version = processRunner.version(path: path)
                return DetectedDependency(id: id, displayName: displayName, available: true, version: version, path: path)
            }
        }
        return DetectedDependency(
            id: id,
            displayName: displayName,
            available: false,
            notes: "Not found on PATH or known install locations (MacPorts / Homebrew / /usr/local)"
        )
    }
}

public protocol ProcessRunnerLike: Sendable {
    func which(_ name: String) -> String?
    func version(path: String) -> String?
    func run(executable: String, arguments: [String]) async throws -> Int32
}

public struct WhichProcessRunner: ProcessRunnerLike {
    public init() {}

    public func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty { return path }
        } catch {}
        return nil
    }

    public func version(path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        // MacPorts `port` does not accept `--version`; use `version`.
        if path.hasSuffix("/port") || (path as NSString).lastPathComponent == "port" {
            process.arguments = ["version"]
        } else {
            process.arguments = ["--version"]
        }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        do {
            try process.run()
            // Bound version probes — unknown CLIs (e.g. hermes stubs) can hang forever.
            let deadline = Date().addingTimeInterval(1.5)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                return nil
            }
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.split(separator: "\n").first.map(String.init)
        } catch {
            return nil
        }
    }

    public func run(executable: String, arguments: [String]) async throws -> Int32 {
        let process = Process()
        // Resolve brew/node via which when needed
        if executable == "brew", let brew = which("brew") {
            process.executableURL = URL(fileURLWithPath: brew)
        } else {
            process.executableURL = URL(fileURLWithPath: executable.hasPrefix("/") ? executable : (which(executable) ?? executable))
        }
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
