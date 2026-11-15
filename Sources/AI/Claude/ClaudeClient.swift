import Foundation
import Core
import Instagram

public protocol ClaudeAPIClient: Sendable {
    func createMessage(
        model: String,
        messages: [ClaudeMessage],
        tools: [ClaudeToolDefinition],
        maxTokens: Int,
        system: String?
    ) async throws -> ClaudeResponse

    func streamMessage(
        model: String,
        messages: [ClaudeMessage],
        tools: [ClaudeToolDefinition],
        maxTokens: Int,
        system: String?
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error>
}

public final class ClaudeClient: ClaudeAPIClient, @unchecked Sendable {
    private let configuration: AppConfiguration
    private let keychain: KeychainStore
    private let http: HTTPClient
    private let retryPolicy: RetryPolicy
    private let anthropicVersion: String

    public init(
        configuration: AppConfiguration,
        keychain: KeychainStore,
        http: HTTPClient = URLSessionHTTPClient(),
        retryPolicy: RetryPolicy = RetryPolicy(),
        anthropicVersion: String = "2023-06-01"
    ) {
        self.configuration = configuration
        self.keychain = keychain
        self.http = http
        self.retryPolicy = retryPolicy
        self.anthropicVersion = anthropicVersion
    }

    public func createMessage(
        model: String,
        messages: [ClaudeMessage],
        tools: [ClaudeToolDefinition],
        maxTokens: Int,
        system: String?
    ) async throws -> ClaudeResponse {
        try await withRetry(policy: retryPolicy) {
            try await self.sendOnce(
                model: model,
                messages: messages,
                tools: tools,
                maxTokens: maxTokens,
                system: system,
                stream: false
            )
        }
    }

    public func streamMessage(
        model: String,
        messages: [ClaudeMessage],
        tools: [ClaudeToolDefinition],
        maxTokens: Int,
        system: String?
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let events = try await self.performStream(
                        model: model,
                        messages: messages,
                        tools: tools,
                        maxTokens: maxTokens,
                        system: system
                    )
                    for event in events {
                        try Task.checkCancellation()
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func apiKey() throws -> String {
        guard let key = try keychain.getSecret(account: KeychainAccount.anthropicAPIKey), !key.isEmpty else {
            throw AppError.authentication("Anthropic API key not found in Keychain")
        }
        return key
    }

    private func sendOnce(
        model: String,
        messages: [ClaudeMessage],
        tools: [ClaudeToolDefinition],
        maxTokens: Int,
        system: String?,
        stream: Bool
    ) async throws -> ClaudeResponse {
        let body = try buildBody(model: model, messages: messages, tools: tools, maxTokens: maxTokens, system: system, stream: stream)
        var request = URLRequest(url: configuration.claudeAPIBaseURL.appendingPathComponent("v1/messages"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.defaultRequestTimeout
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await http.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Invalid Claude response")
        }
        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            throw AppError.rateLimited(retryAfter: retryAfter)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ErrorClassifier.classifyHTTP(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }
        return try decodeResponse(data)
    }

    private func performStream(
        model: String,
        messages: [ClaudeMessage],
        tools: [ClaudeToolDefinition],
        maxTokens: Int,
        system: String?
    ) async throws -> [ClaudeStreamEvent] {
        // Fixture-friendly streaming: if HTTP client returns a full message JSON, emit synthetic stream events.
        // Live SSE parsing is implemented for text when Content-Type is event-stream.
        let body = try buildBody(model: model, messages: messages, tools: tools, maxTokens: maxTokens, system: system, stream: true)
        var request = URLRequest(url: configuration.claudeAPIBaseURL.appendingPathComponent("v1/messages"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.defaultRequestTimeout
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await http.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Invalid Claude stream response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ErrorClassifier.classifyHTTP(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("text/event-stream") {
            return parseSSE(data)
        }
        // Non-SSE (fixtures): convert response to stream events.
        let message = try decodeResponse(data)
        var events: [ClaudeStreamEvent] = [.messageStart(id: message.id, model: message.model)]
        for block in message.content {
            switch block {
            case .text(let text):
                events.append(.textDelta(text))
            case .toolUse(let id, let name, _):
                events.append(.toolUseStart(id: id, name: name))
            default:
                break
            }
        }
        events.append(.messageDelta(stopReason: message.stopReason, usage: message.usage))
        events.append(.messageStop)
        return events
    }

    private func parseSSE(_ data: Data) -> [ClaudeStreamEvent] {
        guard let text = String(data: data, encoding: .utf8) else { return [.error("Invalid SSE encoding")] }
        var events: [ClaudeStreamEvent] = []
        for block in text.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n")
            var eventName = ""
            var dataLine = ""
            for line in lines {
                if line.hasPrefix("event:") {
                    eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    dataLine = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                }
            }
            guard let payload = dataLine.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { continue }
            switch eventName {
            case "message_start":
                if let message = json["message"] as? [String: Any] {
                    events.append(.messageStart(id: message["id"] as? String ?? "", model: message["model"] as? String ?? ""))
                }
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any] {
                    if let t = delta["text"] as? String {
                        events.append(.textDelta(t))
                    } else if let partial = delta["partial_json"] as? String {
                        events.append(.toolUseInputDelta(partial))
                    }
                }
            case "content_block_start":
                if let block = json["content_block"] as? [String: Any], block["type"] as? String == "tool_use" {
                    events.append(.toolUseStart(id: block["id"] as? String ?? "", name: block["name"] as? String ?? ""))
                }
            case "message_delta":
                let stop = (json["delta"] as? [String: Any])?["stop_reason"] as? String
                events.append(.messageDelta(stopReason: stop, usage: nil))
            case "message_stop":
                events.append(.messageStop)
            case "error":
                events.append(.error(String(describing: json)))
            default:
                break
            }
        }
        return events
    }

    private func buildBody(
        model: String,
        messages: [ClaudeMessage],
        tools: [ClaudeToolDefinition],
        maxTokens: Int,
        system: String?,
        stream: Bool
    ) throws -> Data {
        var root: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": stream,
            "messages": try messages.map { try encodeToDictionary($0) }
        ]
        if let system { root["system"] = system }
        if !tools.isEmpty {
            root["tools"] = try tools.map { tool -> [String: Any] in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": try encodeToDictionary(tool.inputSchema)
                ]
            }
        }
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func encodeToDictionary<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func decodeResponse(_ data: Data) throws -> ClaudeResponse {
        struct Raw: Decodable {
            let id: String
            let model: String
            let role: String?
            let content: [ClaudeContentBlock]
            let stop_reason: String?
            let usage: Usage?
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
            }
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        return ClaudeResponse(
            id: raw.id,
            model: raw.model,
            role: raw.role ?? "assistant",
            content: raw.content,
            stopReason: raw.stop_reason,
            usage: ClaudeUsage(
                inputTokens: raw.usage?.input_tokens ?? 0,
                outputTokens: raw.usage?.output_tokens ?? 0
            )
        )
    }
}

/// Deterministic client for tests — never invents Instagram metrics.
public final class FixtureClaudeClient: ClaudeAPIClient, @unchecked Sendable {
    public var nextResponse: ClaudeResponse
    public private(set) var receivedMessages: [[ClaudeMessage]] = []
    private let lock = NSLock()

    public init(nextResponse: ClaudeResponse) {
        self.nextResponse = nextResponse
    }

    public func createMessage(
        model: String,
        messages: [ClaudeMessage],
        tools: [ClaudeToolDefinition],
        maxTokens: Int,
        system: String?
    ) async throws -> ClaudeResponse {
        receivedMessages.append(messages)
        return nextResponse
    }

    public func streamMessage(
        model: String,
        messages: [ClaudeMessage],
        tools: [ClaudeToolDefinition],
        maxTokens: Int,
        system: String?
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        let response = nextResponse
        return AsyncThrowingStream { continuation in
            continuation.yield(.messageStart(id: response.id, model: response.model))
            continuation.yield(.textDelta(response.text))
            continuation.yield(.messageStop)
            continuation.finish()
        }
    }
}
