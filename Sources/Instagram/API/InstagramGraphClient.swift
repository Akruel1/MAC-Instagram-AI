import Foundation
import Core

public struct InstagramAccountDTO: Sendable, Equatable, Codable {
    public var id: String
    public var username: String
    public var accountType: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case accountType = "account_type"
    }

    public init(id: String, username: String, accountType: String? = nil) {
        self.id = id
        self.username = username
        self.accountType = accountType
    }
}

public struct InstagramMediaDTO: Sendable, Equatable, Codable {
    public var id: String
    public var mediaType: String
    public var caption: String?
    public var permalink: String?
    public var timestamp: String?

    enum CodingKeys: String, CodingKey {
        case id, caption, permalink, timestamp
        case mediaType = "media_type"
    }

    public init(
        id: String,
        mediaType: String,
        caption: String? = nil,
        permalink: String? = nil,
        timestamp: String? = nil
    ) {
        self.id = id
        self.mediaType = mediaType
        self.caption = caption
        self.permalink = permalink
        self.timestamp = timestamp
    }
}

public struct InsightMetricDTO: Sendable, Equatable, Codable {
    public var name: String
    public var period: String
    public var values: [InsightValueDTO]
    public var title: String?
    public var description: String?

    public init(
        name: String,
        period: String,
        values: [InsightValueDTO],
        title: String? = nil,
        description: String? = nil
    ) {
        self.name = name
        self.period = period
        self.values = values
        self.title = title
        self.description = description
    }
}

public struct InsightValueDTO: Sendable, Equatable, Codable {
    public var value: Double?
    public var endTime: String?

    enum CodingKeys: String, CodingKey {
        case value
        case endTime = "end_time"
    }

    public init(value: Double?, endTime: String? = nil) {
        self.value = value
        self.endTime = endTime
    }
}

public actor InstagramGraphClient {
    private let configuration: AppConfiguration
    private let http: HTTPClient
    private let tokenProvider: @Sendable () async throws -> String

    public init(
        configuration: AppConfiguration,
        http: HTTPClient = URLSessionHTTPClient(),
        tokenProvider: @escaping @Sendable () async throws -> String
    ) {
        self.configuration = configuration
        self.http = http
        self.tokenProvider = tokenProvider
    }

    public func fetchMe() async throws -> InstagramAccountDTO {
        let token = try await tokenProvider()
        let data = try await get(path: "me", query: [
            "fields": "id,username,account_type",
            "access_token": token
        ])
        return try JSONDecoder().decode(InstagramAccountDTO.self, from: data)
    }

    public func fetchMedia(userID: String, limit: Int = 25) async throws -> [InstagramMediaDTO] {
        let token = try await tokenProvider()
        let data = try await get(path: "\(userID)/media", query: [
            "fields": "id,media_type,caption,permalink,timestamp",
            "limit": String(limit),
            "access_token": token
        ])
        struct Envelope: Decodable { let data: [InstagramMediaDTO] }
        return try JSONDecoder().decode(Envelope.self, from: data).data
    }

    public func fetchAccountInsights(
        userID: String,
        metrics: [String],
        period: String = "day"
    ) async throws -> [InsightMetricDTO] {
        let token = try await tokenProvider()
        let data = try await get(path: "\(userID)/insights", query: [
            "metric": metrics.joined(separator: ","),
            "period": period,
            "access_token": token
        ])
        return try decodeInsights(data)
    }

    public func fetchMediaInsights(mediaID: String, metrics: [String]) async throws -> [InsightMetricDTO] {
        let token = try await tokenProvider()
        let data = try await get(path: "\(mediaID)/insights", query: [
            "metric": metrics.joined(separator: ","),
            "access_token": token
        ])
        return try decodeInsights(data)
    }

    private func decodeInsights(_ data: Data) throws -> [InsightMetricDTO] {
        // Empty dataset means missing/unavailable — never invent zeros.
        if data.isEmpty { return [] }
        struct Envelope: Decodable { let data: [InsightMetricDTO]? }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        return envelope.data ?? []
    }

    private func get(path: String, query: [String: String]) async throws -> Data {
        var components = URLComponents(
            url: configuration.instagramGraphBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            throw AppError.validation("Invalid Graph URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = configuration.defaultRequestTimeout
        let (data, response) = try await http.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Invalid response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ErrorClassifier.classifyHTTP(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }
        return data
    }
}
