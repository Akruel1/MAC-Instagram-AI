import Foundation
import Core

public protocol MCPTransport: Sendable {
    func start() async throws
    func stop() async
    func send(request: MCPRequest) async throws -> MCPResponse
    func isHealthy() async -> Bool
}

public struct MCPRequest: Sendable, Equatable, Codable {
    public var jsonrpc: String = "2.0"
    public var id: String
    public var method: String
    public var params: [String: MCPJSONValue]?

    public init(id: String = UUID().uuidString, method: String, params: [String: MCPJSONValue]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct MCPResponse: Sendable, Equatable, Codable {
    public var jsonrpc: String?
    public var id: String?
    public var result: MCPJSONValue?
    public var error: MCPErrorPayload?

    public init(jsonrpc: String? = "2.0", id: String? = nil, result: MCPJSONValue? = nil, error: MCPErrorPayload? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct MCPErrorPayload: Sendable, Equatable, Codable {
    public var code: Int
    public var message: String
}

public enum MCPJSONValue: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: MCPJSONValue])
    case array([MCPJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let n = try? container.decode(Double.self) { self = .number(n); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let a = try? container.decode([MCPJSONValue].self) { self = .array(a); return }
        if let o = try? container.decode([String: MCPJSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }
}

public struct MCPToolDefinition: Sendable, Equatable, Codable {
    public var name: String
    public var description: String?
    public var inputSchema: [String: MCPJSONValue]?

    public init(name: String, description: String? = nil, inputSchema: [String: MCPJSONValue]? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// Local stdio MCP client. Spawns a reviewed command and speaks JSON-RPC over stdin/stdout.
public actor MCPStdioClient: MCPTransport {
    public let command: String
    public let arguments: [String]
    public let timeout: TimeInterval
    private let logger: Logger

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var buffer = Data()
    private var started = false

    public init(command: String, arguments: [String] = [], timeout: TimeInterval = 30, logger: Logger = StructuredLogger(category: "mcp")) {
        self.command = command
        self.arguments = arguments
        self.timeout = timeout
        self.logger = logger
    }

    public func start() async throws {
        if started { return }
        try PathSafety.assertNoShellMetacharacters(command, label: "mcp.command")
        for arg in arguments {
            try PathSafety.assertNoShellMetacharacters(arg, label: "mcp.arg")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw AppError.dependency("Failed to start MCP process: \(error.localizedDescription)")
        }

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.started = true
        logger.info("MCP process started", metadata: ["command": command])

        // Initialize handshake (best-effort for servers that require it)
        _ = try? await send(request: MCPRequest(method: "initialize", params: [
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object([:]),
            "clientInfo": .object([
                "name": .string("instagram-ai-studio"),
                "version": .string("0.1.0")
            ])
        ]))
        _ = try? await send(request: MCPRequest(method: "notifications/initialized", params: nil))
    }

    public func stop() async {
        process?.terminate()
        try? stdinHandle?.close()
        try? stdoutHandle?.close()
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        started = false
        buffer = Data()
    }

    public func isHealthy() async -> Bool {
        guard let process, started else { return false }
        return process.isRunning
    }

    public func listTools() async throws -> [MCPToolDefinition] {
        let response = try await send(request: MCPRequest(method: "tools/list"))
        if let error = response.error {
            throw AppError.external(service: "mcp", message: error.message)
        }
        guard case .object(let result)? = response.result,
              case .array(let tools)? = result["tools"] else {
            return []
        }
        return tools.compactMap { value in
            guard case .object(let obj) = value,
                  case .string(let name)? = obj["name"] else { return nil }
            let description: String?
            if case .string(let d)? = obj["description"] { description = d } else { description = nil }
            let schema: [String: MCPJSONValue]?
            if case .object(let s)? = obj["inputSchema"] { schema = s } else { schema = nil }
            return MCPToolDefinition(name: name, description: description, inputSchema: schema)
        }
    }

    public func callTool(name: String, arguments: [String: MCPJSONValue] = [:]) async throws -> MCPJSONValue {
        // Tool descriptions and results are untrusted input — callers must treat them as such.
        let response = try await send(request: MCPRequest(method: "tools/call", params: [
            "name": .string(name),
            "arguments": .object(arguments)
        ]))
        if let error = response.error {
            throw AppError.external(service: "mcp", message: error.message)
        }
        return response.result ?? .null
    }

    public func send(request: MCPRequest) async throws -> MCPResponse {
        guard started, let stdinHandle, let stdoutHandle else {
            throw AppError.dependency("MCP client not started")
        }
        if request.method != "notifications/initialized" {
            // notifications may omit id in real MCP; we still send for fixture simplicity
        }
        let data = try JSONEncoder().encode(request)
        guard var line = String(data: data, encoding: .utf8) else {
            throw AppError.validation("Failed to encode MCP request")
        }
        line.append("\n")
        guard let payload = line.data(using: .utf8) else {
            throw AppError.validation("Failed to encode MCP request line")
        }

        return try await withTimeout(seconds: timeout) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MCPResponse, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try stdinHandle.write(contentsOf: payload)
                        // Read until newline
                        var collected = Data()
                        while true {
                            let chunk = try stdoutHandle.read(upToCount: 1) ?? Data()
                            if chunk.isEmpty {
                                throw AppError.external(service: "mcp", message: "EOF from MCP server")
                            }
                            collected.append(chunk)
                            if chunk == Data([0x0A]) { break }
                            if collected.count > 1_000_000 {
                                throw AppError.external(service: "mcp", message: "MCP response too large")
                            }
                        }
                        let response = try JSONDecoder().decode(MCPResponse.self, from: collected)
                        continuation.resume(returning: response)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

/// In-process transport for unit tests.
public actor MCPInMemoryTransport: MCPTransport {
    public var tools: [MCPToolDefinition]
    public var callHandler: @Sendable (String, [String: MCPJSONValue]) async throws -> MCPJSONValue
    private var healthy = false

    public init(
        tools: [MCPToolDefinition] = [MCPToolDefinition(name: "echo", description: "Echo")],
        callHandler: @escaping @Sendable (String, [String: MCPJSONValue]) async throws -> MCPJSONValue = { name, args in
            .object(["tool": .string(name), "args": .object(args)])
        }
    ) {
        self.tools = tools
        self.callHandler = callHandler
    }

    public func start() async throws { healthy = true }
    public func stop() async { healthy = false }
    public func isHealthy() async -> Bool { healthy }

    public func send(request: MCPRequest) async throws -> MCPResponse {
        switch request.method {
        case "tools/list":
            let encoded = tools.map { tool -> MCPJSONValue in
                var obj: [String: MCPJSONValue] = ["name": .string(tool.name)]
                if let d = tool.description { obj["description"] = .string(d) }
                if let s = tool.inputSchema { obj["inputSchema"] = .object(s) }
                return .object(obj)
            }
            return MCPResponse(id: request.id, result: .object(["tools": .array(encoded)]))
        case "tools/call":
            guard case .string(let name)? = request.params?["name"] else {
                return MCPResponse(id: request.id, error: MCPErrorPayload(code: -32602, message: "Missing tool name"))
            }
            let args: [String: MCPJSONValue]
            if case .object(let o)? = request.params?["arguments"] { args = o } else { args = [:] }
            let result = try await callHandler(name, args)
            return MCPResponse(id: request.id, result: result)
        case "initialize", "notifications/initialized":
            return MCPResponse(id: request.id, result: .object([:]))
        default:
            return MCPResponse(id: request.id, error: MCPErrorPayload(code: -32601, message: "Method not found"))
        }
    }
}
