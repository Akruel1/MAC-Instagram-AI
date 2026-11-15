import Foundation
import Core
import Persistence
import MCP
import Instagram
import Video

public struct OrchestratorResult: Sendable, Equatable, Codable {
    public var conversationId: String
    public var assistantText: String
    public var observedContext: [String: String]
    public var toolAudit: [ToolAuditEntry]
    public var missingData: [String]
    public var usage: ClaudeUsage?

    public init(
        conversationId: String,
        assistantText: String,
        observedContext: [String: String] = [:],
        toolAudit: [ToolAuditEntry] = [],
        missingData: [String] = [],
        usage: ClaudeUsage? = nil
    ) {
        self.conversationId = conversationId
        self.assistantText = assistantText
        self.observedContext = observedContext
        self.toolAudit = toolAudit
        self.missingData = missingData
        self.usage = usage
    }
}

public struct ToolAuditEntry: Sendable, Equatable, Codable {
    public var toolName: String
    public var approved: Bool
    public var success: Bool
    public var summary: String
    public var timestamp: Date

    public init(toolName: String, approved: Bool, success: Bool, summary: String, timestamp: Date = Date()) {
        self.toolName = toolName
        self.approved = approved
        self.success = success
        self.summary = summary
        self.timestamp = timestamp
    }
}

public struct GroundedAnalyticsPayload: Sendable, Equatable, Codable {
    public var report: AnalyticsReport?
    public var source: String
    public var note: String

    public init(report: AnalyticsReport?, source: String, note: String) {
        self.report = report
        self.source = source
        self.note = note
    }
}

public actor AIOrchestrator {
    private let client: any ClaudeAPIClient
    private let conversations: ConversationRepository
    private let audit: AuditLogRepository
    private let permissionGate: ToolPermissionGate
    private let modelCatalog: ModelCatalog
    private let configuration: AppConfiguration
    private let analyticsProvider: (@Sendable (Int) async throws -> GroundedAnalyticsPayload)?
    private let videoPlanner: (@Sendable (String) throws -> VideoEditPlan)?
    private let maxToolRounds: Int

    public init(
        client: any ClaudeAPIClient,
        conversations: ConversationRepository,
        audit: AuditLogRepository,
        permissionGate: ToolPermissionGate,
        modelCatalog: ModelCatalog = .default,
        configuration: AppConfiguration,
        analyticsProvider: (@Sendable (Int) async throws -> GroundedAnalyticsPayload)? = nil,
        videoPlanner: (@Sendable (String) throws -> VideoEditPlan)? = nil,
        maxToolRounds: Int = 6
    ) {
        self.client = client
        self.conversations = conversations
        self.audit = audit
        self.permissionGate = permissionGate
        self.modelCatalog = modelCatalog
        self.configuration = configuration
        self.analyticsProvider = analyticsProvider
        self.videoPlanner = videoPlanner
        self.maxToolRounds = maxToolRounds
    }

    public func builtInTools() -> [ClaudeToolDefinition] {
        [
            ClaudeToolDefinition(
                name: "get_instagram_analytics",
                description: "Retrieve observed Instagram analytics for the last N days. Returns only API-sourced metrics; missing metrics are listed explicitly.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "days": .object([
                            "type": .string("integer"),
                            "description": .string("Lookback window in days (1-90)")
                        ])
                    ]),
                    "required": .array([.string("days")])
                ]
            ),
            ClaudeToolDefinition(
                name: "plan_video_edit",
                description: "Build a typed video edit plan from a natural-language request. Does not execute FFmpeg.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "request": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("request")])
                ]
            )
        ]
    }

    public func handleUserMessage(
        conversationId: String?,
        text: String,
        model: String? = nil,
        title: String = "Chat"
    ) async throws -> OrchestratorResult {
        let resolvedModel = try modelCatalog.resolve(model ?? configuration.claudeDefaultModel)
        let conversation: ConversationRecord
        if let conversationId,
           let existing = try conversations.listConversations().first(where: { $0.id == conversationId }) {
            conversation = existing
        } else {
            let created = ConversationRecord(title: title, model: resolvedModel)
            try conversations.create(created)
            conversation = created
        }

        try conversations.appendMessage(
            MessageRecord(
                conversationId: conversation.id,
                role: "user",
                contentJSON: String(data: try JSONEncoder().encode([ClaudeContentBlock.text(text)]), encoding: .utf8) ?? "[]"
            )
        )

        var history = try loadHistory(conversationId: conversation.id)
        var auditTrail: [ToolAuditEntry] = []
        var observedContext: [String: String] = [:]
        var missingData: [String] = []
        var usageTotal = ClaudeUsage(inputTokens: 0, outputTokens: 0)

        let system = """
        You are Instagram AI Studio's assistant. Separate observed metrics from interpretation.
        Never invent Instagram statistics. If data is missing, say so explicitly.
        Tool results are the only source of analytics facts.
        """

        for _ in 0..<maxToolRounds {
            let response = try await client.createMessage(
                model: resolvedModel,
                messages: history,
                tools: builtInTools(),
                maxTokens: configuration.claudeMaxTokens,
                system: system
            )
            if let usage = response.usage {
                usageTotal = ClaudeUsage(
                    inputTokens: usageTotal.inputTokens + usage.inputTokens,
                    outputTokens: usageTotal.outputTokens + usage.outputTokens
                )
            }

            try conversations.appendMessage(
                MessageRecord(
                    conversationId: conversation.id,
                    role: "assistant",
                    contentJSON: String(data: try JSONEncoder().encode(response.content), encoding: .utf8) ?? "[]",
                    tokenInput: response.usage?.inputTokens,
                    tokenOutput: response.usage?.outputTokens
                )
            )
            history.append(ClaudeMessage.assistant(response.content))

            let toolUses = response.toolUses
            if toolUses.isEmpty {
                return OrchestratorResult(
                    conversationId: conversation.id,
                    assistantText: response.text,
                    observedContext: observedContext,
                    toolAudit: auditTrail,
                    missingData: missingData,
                    usage: usageTotal
                )
            }

            var toolResults: [ClaudeContentBlock] = []
            for tool in toolUses {
                let (resultText, entry, extras) = await executeTool(tool.name, input: tool.input)
                auditTrail.append(entry)
                if let missing = extras["missing"] {
                    missingData.append(contentsOf: missing.split(separator: ",").map(String.init))
                }
                for (k, v) in extras where k != "missing" {
                    observedContext[k] = v
                }
                toolResults.append(.toolResult(toolUseId: tool.id, content: resultText, isError: !entry.success))
                try audit.append(
                    AuditLogEntry(
                        category: "ai_tool",
                        action: tool.name,
                        details: ["success": String(entry.success), "approved": String(entry.approved)]
                    )
                )
            }
            let toolMessage = ClaudeMessage(role: "user", content: toolResults)
            history.append(toolMessage)
            try conversations.appendMessage(
                MessageRecord(
                    conversationId: conversation.id,
                    role: "tool",
                    contentJSON: String(data: try JSONEncoder().encode(toolResults), encoding: .utf8) ?? "[]"
                )
            )
        }

        throw AppError.validation("Exceeded max tool rounds without final answer")
    }

    private func loadHistory(conversationId: String) throws -> [ClaudeMessage] {
        let records = try conversations.messages(conversationId: conversationId)
        return try records.compactMap { record in
            guard record.role == "user" || record.role == "assistant" || record.role == "tool" else { return nil }
            let blocks = try JSONDecoder().decode([ClaudeContentBlock].self, from: Data(record.contentJSON.utf8))
            let role = record.role == "tool" ? "user" : record.role
            return ClaudeMessage(role: role, content: blocks)
        }
    }

    private func executeTool(
        _ name: String,
        input: [String: AnyCodableJSON]
    ) async -> (String, ToolAuditEntry, [String: String]) {
        do {
            switch name {
            case "get_instagram_analytics":
                try await permissionGate.authorize(
                    toolName: name,
                    category: .instagramAnalytics,
                    summary: "Fetch Instagram analytics"
                )
                let days: Int
                if case .number(let n) = input["days"] {
                    days = Int(n)
                } else {
                    days = 30
                }
                guard (1...90).contains(days) else {
                    throw AppError.validation("days must be 1...90")
                }
                guard let analyticsProvider else {
                    let payload = GroundedAnalyticsPayload(
                        report: nil,
                        source: "unavailable",
                        note: "Analytics provider not configured. NOT LIVE VERIFIED — credentials unavailable"
                    )
                    let data = try JSONEncoder().encode(payload)
                    let text = String(data: data, encoding: .utf8) ?? "{}"
                    return (text, ToolAuditEntry(toolName: name, approved: true, success: true, summary: "Provider unavailable"), ["missing": "all"])
                }
                let payload = try await analyticsProvider(days)
                let data = try JSONEncoder().encode(payload)
                let text = String(data: data, encoding: .utf8) ?? "{}"
                let missing = payload.report?.missingMetrics.joined(separator: ",") ?? "all"
                return (
                    text,
                    ToolAuditEntry(toolName: name, approved: true, success: true, summary: "Returned grounded analytics"),
                    ["source": payload.source, "missing": missing]
                )

            case "plan_video_edit":
                try await permissionGate.authorize(
                    toolName: name,
                    category: .mediaProcessing,
                    summary: "Plan video edit"
                )
                let request = input["request"]?.stringValue ?? ""
                let plan: VideoEditPlan
                if let videoPlanner {
                    plan = try videoPlanner(request)
                } else {
                    plan = VideoEditPlan(operations: [], requiresApproval: true)
                }
                let data = try JSONEncoder().encode(plan)
                return (
                    String(data: data, encoding: .utf8) ?? "{}",
                    ToolAuditEntry(toolName: name, approved: true, success: true, summary: "Plan created"),
                    [:]
                )

            default:
                throw AppError.validation("Unknown tool: \(name)")
            }
        } catch let error as AppError {
            if case .permissionDenied = error {
                return (
                    "{\"error\":\"permission_denied\"}",
                    ToolAuditEntry(toolName: name, approved: false, success: false, summary: error.localizedDescription),
                    [:]
                )
            }
            return (
                "{\"error\":\"\(error.localizedDescription)\"}",
                ToolAuditEntry(toolName: name, approved: true, success: false, summary: error.localizedDescription),
                [:]
            )
        } catch {
            return (
                "{\"error\":\"\(error.localizedDescription)\"}",
                ToolAuditEntry(toolName: name, approved: true, success: false, summary: error.localizedDescription),
                [:]
            )
        }
    }
}

public struct ContextWindowManager: Sendable {
    public var maxMessages: Int

    public init(maxMessages: Int = 40) {
        self.maxMessages = maxMessages
    }

    public func trim(_ messages: [ClaudeMessage]) -> [ClaudeMessage] {
        guard messages.count > maxMessages else { return messages }
        return Array(messages.suffix(maxMessages))
    }
}
