import Foundation
import Core
import Persistence

public actor MCPServerManager {
    private let registry: MCPRegistry
    private let permissionGate: ToolPermissionGate
    private let audit: AuditLogRepository?
    private let logger: Logger
    private var clients: [String: MCPStdioClient] = [:]
    private var fixtureScriptURL: URL?

    public init(
        registry: MCPRegistry,
        permissionGate: ToolPermissionGate,
        audit: AuditLogRepository? = nil,
        logger: Logger = StructuredLogger(category: "mcp"),
        fixtureScriptURL: URL? = nil
    ) {
        self.registry = registry
        self.permissionGate = permissionGate
        self.audit = audit
        self.logger = logger
        self.fixtureScriptURL = fixtureScriptURL
    }

    public func start(serverId: String) async throws {
        let descriptor = try registry.descriptor(id: serverId)
        var command = descriptor.command
        var args = descriptor.args

        if serverId == "fixture-echo" {
            guard let script = fixtureScriptURL else {
                throw AppError.dependency("Fixture MCP script path not configured")
            }
            command = "/usr/local/bin/node"
            if !FileManager.default.isExecutableFile(atPath: command) {
                // fallback to PATH resolution
                command = "/usr/bin/env"
                args = ["node", script.path]
            } else {
                args = [script.path]
            }
        }

        let client = MCPStdioClient(command: command, arguments: args, logger: logger)
        try await client.start()
        clients[serverId] = client
        try registry.persistEnabled(serverId, enabled: true)
        try audit?.append(AuditLogEntry(category: "mcp", action: "start", details: ["serverId": serverId]))
    }

    public func stop(serverId: String) async throws {
        if let client = clients[serverId] {
            await client.stop()
            clients[serverId] = nil
        }
        try registry.persistEnabled(serverId, enabled: false)
        try audit?.append(AuditLogEntry(category: "mcp", action: "stop", details: ["serverId": serverId]))
    }

    public func health(serverId: String) async -> Bool {
        guard let client = clients[serverId] else { return false }
        return await client.isHealthy()
    }

    public func listTools(serverId: String) async throws -> [MCPToolDefinition] {
        guard let client = clients[serverId] else {
            throw AppError.notFound("MCP server not running: \(serverId)")
        }
        return try await client.listTools()
    }

    public func callTool(
        serverId: String,
        toolName: String,
        arguments: [String: MCPJSONValue],
        category: ToolPermissionCategory
    ) async throws -> MCPJSONValue {
        try await permissionGate.authorize(
            toolName: toolName,
            category: category,
            summary: "Execute MCP tool \(toolName) on \(serverId)",
            details: ["serverId": serverId]
        )
        guard let client = clients[serverId] else {
            throw AppError.notFound("MCP server not running: \(serverId)")
        }
        let result = try await client.callTool(name: toolName, arguments: arguments)
        try audit?.append(
            AuditLogEntry(
                category: "mcp",
                action: "tool_call",
                details: ["serverId": serverId, "tool": toolName]
            )
        )
        return result
    }
}
