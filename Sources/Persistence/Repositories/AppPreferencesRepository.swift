import Foundation
import GRDB
import Core

public struct AppPreferencesRepository: Sendable {
    private let dbQueue: DatabaseQueue

    public init(db: DatabaseManager) {
        self.dbQueue = db.dbQueue
    }

    public func getBool(_ key: String, default defaultValue: Bool = false) throws -> Bool {
        try dbQueue.read { db in
            if let row = try Row.fetchOne(db, sql: "SELECT value FROM app_preferences WHERE key = ?", arguments: [key]),
               let value: String = row["value"] {
                return value == "true" || value == "1"
            }
            return defaultValue
        }
    }

    public func setBool(_ key: String, _ value: Bool) throws {
        try upsert(key: key, value: value ? "true" : "false")
    }

    public func getString(_ key: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM app_preferences WHERE key = ?", arguments: [key])
        }
    }

    public func setString(_ key: String, _ value: String) throws {
        try upsert(key: key, value: value)
    }

    private func upsert(key: String, value: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO app_preferences (key, value, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                """,
                arguments: [key, value, Date()]
            )
        }
    }
}

public enum AppPreferenceKey {
    public static let onboardingCompleted = "onboarding.completed"
    public static let appearance = "ui.appearance"
    public static let displayName = "ui.displayName"
    public static let displayNamePromptCompleted = "ui.displayName.promptCompleted"
}

public enum DisplayNamePolicy {
    public static let maxLength = 32
    public static let fallback = "Welcome"

    public static func sanitize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }
}
