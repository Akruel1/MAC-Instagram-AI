import XCTest
@testable import Persistence
@testable import Core

final class DisplayNamePolicyTests: XCTestCase {
    func testSanitizeTrimsAndRejectsWhitespaceOnly() {
        XCTAssertEqual(DisplayNamePolicy.sanitize("  Ada  "), "Ada")
        XCTAssertNil(DisplayNamePolicy.sanitize("   "))
        XCTAssertNil(DisplayNamePolicy.sanitize(""))
    }

    func testSanitizeEnforcesMaxLength() {
        let long = String(repeating: "a", count: DisplayNamePolicy.maxLength + 10)
        let sanitized = DisplayNamePolicy.sanitize(long)
        XCTAssertEqual(sanitized?.count, DisplayNamePolicy.maxLength)
    }

    func testDisplayNamePersistsAcrossRepository() throws {
        let db = try DatabaseManager.inMemory()
        let prefs = AppPreferencesRepository(db: db)
        XCTAssertNil(try prefs.getString(AppPreferenceKey.displayName))
        try prefs.setString(AppPreferenceKey.displayName, "Andrej")
        XCTAssertEqual(try prefs.getString(AppPreferenceKey.displayName), "Andrej")
        try prefs.setBool(AppPreferenceKey.displayNamePromptCompleted, true)
        XCTAssertTrue(try prefs.getBool(AppPreferenceKey.displayNamePromptCompleted))
    }

    func testExistingInstallMigrationKeysDoNotResetOnboarding() throws {
        let db = try DatabaseManager.inMemory()
        let prefs = AppPreferencesRepository(db: db)
        try prefs.setBool(AppPreferenceKey.onboardingCompleted, true)
        XCTAssertNil(try prefs.getString(AppPreferenceKey.displayName))
        XCTAssertFalse(try prefs.getBool(AppPreferenceKey.displayNamePromptCompleted))
        XCTAssertTrue(try prefs.getBool(AppPreferenceKey.onboardingCompleted))
    }
}
