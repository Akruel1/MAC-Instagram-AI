import Foundation
import Security

public protocol KeychainStore: Sendable {
    func setSecret(_ value: String, account: String) throws
    func getSecret(account: String) throws -> String?
    func deleteSecret(account: String) throws
    func hasSecret(account: String) throws -> Bool
}

public enum KeychainAccount {
    public static let anthropicAPIKey = "anthropic.api-key"
    public static let instagramAccessToken = "instagram.access-token"
    public static let instagramRefreshToken = "instagram.refresh-token"
    public static let telegramBotToken = "telegram.bot-token"
    public static let metaAppSecret = "meta.app-secret"
}

public struct KeychainSecretsStore: KeychainStore {
    public let service: String

    public init(service: String = "com.instagramaistudio") {
        self.service = service
    }

    public func setSecret(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw AppError.validation("Secret is not valid UTF-8")
        }
        try deleteSecret(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError.persistence("Keychain write failed: \(status)")
        }
    }

    public func getSecret(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AppError.persistence("Keychain read failed: \(status)")
        }
        return String(data: data, encoding: .utf8)
    }

    public func deleteSecret(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.persistence("Keychain delete failed: \(status)")
        }
    }

    public func hasSecret(account: String) throws -> Bool {
        try getSecret(account: account) != nil
    }
}

/// In-memory Keychain for tests. Never use in production.
public final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    public init() {}

    public func setSecret(_ value: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = value
    }

    public func getSecret(account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[account]
    }

    public func deleteSecret(account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: account)
    }

    public func hasSecret(account: String) throws -> Bool {
        try getSecret(account: account) != nil
    }
}
