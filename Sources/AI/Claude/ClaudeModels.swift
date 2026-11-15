import Foundation

public struct ClaudeMessage: Sendable, Equatable, Codable {
    public var role: String
    public var content: [ClaudeContentBlock]

    public init(role: String, content: [ClaudeContentBlock]) {
        self.role = role
        self.content = content
    }

    public static func user(_ text: String) -> ClaudeMessage {
        ClaudeMessage(role: "user", content: [.text(text)])
    }

    public static func assistant(_ blocks: [ClaudeContentBlock]) -> ClaudeMessage {
        ClaudeMessage(role: "assistant", content: blocks)
    }
}

public enum ClaudeContentBlock: Sendable, Equatable, Codable {
    case text(String)
    case toolUse(id: String, name: String, input: [String: AnyCodableJSON])
    case toolResult(toolUseId: String, content: String, isError: Bool)

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "tool_use":
            self = .toolUse(
                id: try c.decode(String.self, forKey: .id),
                name: try c.decode(String.self, forKey: .name),
                input: try c.decodeIfPresent([String: AnyCodableJSON].self, forKey: .input) ?? [:]
            )
        case "tool_result":
            self = .toolResult(
                toolUseId: try c.decode(String.self, forKey: .toolUseId),
                content: try c.decode(String.self, forKey: .content),
                isError: try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false
            )
        default:
            self = .text("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            try c.encode("tool_use", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let isError):
            try c.encode("tool_result", forKey: .type)
            try c.encode(toolUseId, forKey: .toolUseId)
            try c.encode(content, forKey: .content)
            try c.encode(isError, forKey: .isError)
        }
    }
}

public enum AnyCodableJSON: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AnyCodableJSON])
    case array([AnyCodableJSON])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([AnyCodableJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: AnyCodableJSON].self) { self = .object(o); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

public struct ClaudeToolDefinition: Sendable, Equatable, Codable {
    public var name: String
    public var description: String
    public var inputSchema: [String: AnyCodableJSON]

    public init(name: String, description: String, inputSchema: [String: AnyCodableJSON]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct ClaudeUsage: Sendable, Equatable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct ClaudeResponse: Sendable, Equatable, Codable {
    public var id: String
    public var model: String
    public var role: String
    public var content: [ClaudeContentBlock]
    public var stopReason: String?
    public var usage: ClaudeUsage?

    public init(
        id: String,
        model: String,
        role: String = "assistant",
        content: [ClaudeContentBlock],
        stopReason: String? = nil,
        usage: ClaudeUsage? = nil
    ) {
        self.id = id
        self.model = model
        self.role = role
        self.content = content
        self.stopReason = stopReason
        self.usage = usage
    }

    public var text: String {
        content.compactMap {
            if case .text(let t) = $0 { return t }
            return nil
        }.joined()
    }

    public var toolUses: [(id: String, name: String, input: [String: AnyCodableJSON])] {
        content.compactMap {
            if case .toolUse(let id, let name, let input) = $0 {
                return (id, name, input)
            }
            return nil
        }
    }
}

public enum ClaudeStreamEvent: Sendable, Equatable {
    case messageStart(id: String, model: String)
    case textDelta(String)
    case toolUseStart(id: String, name: String)
    case toolUseInputDelta(String)
    case messageDelta(stopReason: String?, usage: ClaudeUsage?)
    case messageStop
    case error(String)
}
