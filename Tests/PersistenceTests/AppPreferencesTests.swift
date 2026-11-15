import XCTest
@testable import Persistence
@testable import Core

final class AppPreferencesTests: XCTestCase {
    func testOnboardingFlagRoundTrip() throws {
        let db = try DatabaseManager.inMemory()
        let prefs = AppPreferencesRepository(db: db)
        XCTAssertFalse(try prefs.getBool(AppPreferenceKey.onboardingCompleted))
        try prefs.setBool(AppPreferenceKey.onboardingCompleted, true)
        XCTAssertTrue(try prefs.getBool(AppPreferenceKey.onboardingCompleted))
    }
}
