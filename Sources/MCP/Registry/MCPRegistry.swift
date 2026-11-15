import Foundation
import Core
import Persistence

public struct MCPIntegrationDescriptor: Sendable, Equatable, Codable {
    public var id: String
    public var displayName: String
    public var supportedPlatforms: [String]
    public var requiredDependencies: [String]
    public var installationMethod: String
    public var configurationRequirements: [String]
    public var healthCheckMethod: String
    public var version: String
    public var uninstallProcedure: String
    public var command: String
    public var args: [String]
    public var defaultPermissionCategories: [ToolPermissionCategory]

    public init(
        id: String,
        displayName: String,
        supportedPlatforms: [String] = ["macOS"],
        requiredDependencies: [String] = [],
        installationMethod: String,
        configurationRequirements: [String] = [],
        healthCheckMethod: String,
        version: String,
        uninstallProcedure: String,
        command: String,
        args: [String] = [],
        defaultPermissionCategories: [ToolPermissionCategory] = [.networkAccess]
    ) {
        self.id = id
        self.displayName = displayName
        self.supportedPlatforms = supportedPlatforms
        self.requiredDependencies = requiredDependencies
        self.installationMethod = installationMethod
        self.configurationRequirements = configurationRequirements
        self.healthCheckMethod = healthCheckMethod
        self.version = version
        self.uninstallProcedure = uninstallProcedure
        self.command = command
        self.args = args
        self.defaultPermissionCategories = defaultPermissionCategories
    }
}

public struct MCPRegistry: Sendable {
    public let reviewedIntegrations: [MCPIntegrationDescriptor]
    private let repository: MCPRegistryRepository?

    public init(repository: MCPRegistryRepository? = nil, reviewedIntegrations: [MCPIntegrationDescriptor]? = nil) {
        self.repository = repository
        self.reviewedIntegrations = reviewedIntegrations ?? Self.builtInReviewedIntegrations()
    }

    public func descriptor(id: String) throws -> MCPIntegrationDescriptor {
        guard let match = reviewedIntegrations.first(where: { $0.id == id }) else {
            throw AppError.notFound("MCP integration not reviewed: \(id)")
        }
        return match
    }

    public func persistEnabled(_ id: String, enabled: Bool) throws {
        let desc = try descriptor(id: id)
        guard let repository else { return }
        try repository.upsert(
            MCPServerRecord(
                id: desc.id,
                displayName: desc.displayName,
                command: desc.command,
                args: desc.args,
                enabled: enabled,
                version: desc.version,
                installedAt: enabled ? Date() : nil
            )
        )
    }

    public static func builtInReviewedIntegrations() -> [MCPIntegrationDescriptor] {
        [
            MCPIntegrationDescriptor(
                id: "fixture-echo",
                displayName: "Fixture Echo MCP",
                requiredDependencies: ["node"],
                installationMethod: "bundled-fixture",
                configurationRequirements: [],
                healthCheckMethod: "tools/list",
                version: "1.0.0",
                uninstallProcedure: "disable-in-registry",
                command: "node",
                args: [],
                defaultPermissionCategories: [.networkAccess]
            )
        ]
    }
}
