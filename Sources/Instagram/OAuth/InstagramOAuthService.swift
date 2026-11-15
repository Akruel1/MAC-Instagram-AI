import Foundation
import CryptoKit
import Core

public struct OAuthSession: Sendable, Equatable, Codable {
    public var state: String
    public var codeVerifier: String
    public var createdAt: Date

    public init(state: String, codeVerifier: String, createdAt: Date = Date()) {
        self.state = state
        self.codeVerifier = codeVerifier
        self.createdAt = createdAt
    }
}

public struct InstagramTokenSet: Sendable, Equatable, Codable {
    public var accessToken: String
    public var tokenType: String?
    public var expiresIn: TimeInterval?
    public var obtainedAt: Date
    public var userID: String?

    public init(
        accessToken: String,
        tokenType: String? = "bearer",
        expiresIn: TimeInterval? = nil,
        obtainedAt: Date = Date(),
        userID: String? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.obtainedAt = obtainedAt
        self.userID = userID
    }

    public var isExpired: Bool {
        guard let expiresIn else { return false }
        return Date() >= obtainedAt.addingTimeInterval(expiresIn - 60)
    }
}

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public struct FixtureHTTPClient: HTTPClient {
    public var handlers: [String: (Data, Int)]

    public init(handlers: [String: (Data, Int)] = [:]) {
        self.handlers = handlers
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        // Prefer longest path-segment match so "me" does not steal URLs containing "metric".
        let ranked = handlers
            .map { entry -> (score: Int, payload: (Data, Int))? in
                let key = entry.key
                if path == "/\(key)" || path.hasSuffix("/\(key)") {
                    return (key.count + 100, entry.value)
                }
                if path.split(separator: "/").map(String.init).contains(key) {
                    return (key.count + 50, entry.value)
                }
                return nil
            }
            .compactMap { $0 }
            .sorted { $0.score > $1.score }
        guard let match = ranked.first?.payload else {
            throw AppError.network("No fixture for \(request.url?.absoluteString ?? "")")
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: match.1,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (match.0, response)
    }
}

public actor InstagramOAuthService {
    private let configuration: AppConfiguration
    private let keychain: KeychainStore
    private let http: HTTPClient
    private var pending: OAuthSession?

    public init(configuration: AppConfiguration, keychain: KeychainStore, http: HTTPClient = URLSessionHTTPClient()) {
        self.configuration = configuration
        self.keychain = keychain
        self.http = http
    }

    public func beginAuthorization(scopes: [String] = [
        "instagram_business_basic",
        "instagram_business_manage_insights"
    ]) throws -> (url: URL, session: OAuthSession) {
        guard let appID = configuration.metaAppID, !appID.isEmpty else {
            throw AppError.configuration("META_APP_ID is required for Instagram OAuth")
        }
        let state = Self.randomURLSafe(32)
        let verifier = Self.randomURLSafe(64)
        let challenge = Self.codeChallenge(for: verifier)
        let session = OAuthSession(state: state, codeVerifier: verifier)
        pending = session

        var components = URLComponents(url: configuration.instagramOAuthBaseURL.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: appID),
            URLQueryItem(name: "redirect_uri", value: configuration.metaRedirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: ",")),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else {
            throw AppError.configuration("Failed to build OAuth URL")
        }
        return (url, session)
    }

    public func completeAuthorization(callbackURL: URL) async throws -> InstagramTokenSet {
        guard let pending else {
            throw AppError.authentication("No pending OAuth session")
        }
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
        guard let state = items["state"], state == pending.state else {
            throw AppError.authentication("Invalid OAuth state")
        }
        if let error = items["error"] {
            throw AppError.authentication(items["error_description"] ?? error)
        }
        guard let code = items["code"] else {
            throw AppError.authentication("Missing authorization code")
        }
        return try await exchangeCode(code, verifier: pending.codeVerifier)
    }

    public func completeWithCode(_ code: String, expectedState: String) async throws -> InstagramTokenSet {
        guard let pending, pending.state == expectedState else {
            throw AppError.authentication("Invalid OAuth state")
        }
        return try await exchangeCode(code, verifier: pending.codeVerifier)
    }

    public func storedToken() throws -> InstagramTokenSet? {
        guard let token = try keychain.getSecret(account: KeychainAccount.instagramAccessToken) else {
            return nil
        }
        // Metadata (expiry/user) stored as companion JSON is optional; token itself is in Keychain.
        let metaJSON = try keychain.getSecret(account: KeychainAccount.instagramAccessToken + ".meta")
        if let metaJSON, let data = metaJSON.data(using: .utf8),
           var decoded = try? JSONDecoder().decode(InstagramTokenSet.self, from: data) {
            decoded.accessToken = token
            return decoded
        }
        return InstagramTokenSet(accessToken: token)
    }

    public func clearTokens() throws {
        try keychain.deleteSecret(account: KeychainAccount.instagramAccessToken)
        try keychain.deleteSecret(account: KeychainAccount.instagramAccessToken + ".meta")
        try keychain.deleteSecret(account: KeychainAccount.instagramRefreshToken)
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> InstagramTokenSet {
        guard let appID = configuration.metaAppID else {
            throw AppError.configuration("META_APP_ID missing")
        }
        let appSecret = try keychain.getSecret(account: KeychainAccount.metaAppSecret)

        var request = URLRequest(url: configuration.instagramGraphBaseURL.appendingPathComponent("oauth/access_token"))
        // Instagram Login short-lived token exchange commonly uses api.instagram.com
        request = URLRequest(url: URL(string: "https://api.instagram.com/oauth/access_token")!)
        request.httpMethod = "POST"
        var body: [String: String] = [
            "client_id": appID,
            "grant_type": "authorization_code",
            "redirect_uri": configuration.metaRedirectURI,
            "code": code,
            "code_verifier": verifier
        ]
        if let appSecret { body["client_secret"] = appSecret }
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await http.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Invalid token response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8)
            throw ErrorClassifier.classifyHTTP(status: httpResponse.statusCode, body: bodyText)
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let token_type: String?
            let expires_in: TimeInterval?
            let user_id: Int64?
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        var tokenSet = InstagramTokenSet(
            accessToken: decoded.access_token,
            tokenType: decoded.token_type,
            expiresIn: decoded.expires_in,
            userID: decoded.user_id.map(String.init)
        )
        // Attempt long-lived exchange when app secret is available.
        if appSecret != nil {
            tokenSet = try await exchangeLongLived(shortLived: tokenSet) ?? tokenSet
        }
        try persist(tokenSet)
        pending = nil
        return tokenSet
    }

    private func exchangeLongLived(shortLived: InstagramTokenSet) async throws -> InstagramTokenSet? {
        guard let appSecret = try keychain.getSecret(account: KeychainAccount.metaAppSecret) else {
            return nil
        }
        var components = URLComponents(url: configuration.instagramGraphBaseURL.appendingPathComponent("access_token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "ig_exchange_token"),
            URLQueryItem(name: "client_secret", value: appSecret),
            URLQueryItem(name: "access_token", value: shortLived.accessToken)
        ]
        guard let url = components.url else { return nil }
        let (data, response) = try await http.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }
        struct LongLived: Decodable {
            let access_token: String
            let token_type: String?
            let expires_in: TimeInterval?
        }
        let decoded = try JSONDecoder().decode(LongLived.self, from: data)
        return InstagramTokenSet(
            accessToken: decoded.access_token,
            tokenType: decoded.token_type,
            expiresIn: decoded.expires_in,
            userID: shortLived.userID
        )
    }

    private func persist(_ tokenSet: InstagramTokenSet) throws {
        try keychain.setSecret(tokenSet.accessToken, account: KeychainAccount.instagramAccessToken)
        var meta = tokenSet
        meta.accessToken = "" // do not duplicate token in meta blob
        let data = try JSONEncoder().encode(meta)
        if let json = String(data: data, encoding: .utf8) {
            try keychain.setSecret(json, account: KeychainAccount.instagramAccessToken + ".meta")
        }
    }

    private static func randomURLSafe(_ byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
