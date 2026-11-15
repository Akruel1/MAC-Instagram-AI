import XCTest
@testable import Instagram
@testable import Core
@testable import Persistence

final class InstagramTests: XCTestCase {
    func testOAuthStateValidation() async throws {
        let keychain = InMemoryKeychainStore()
        let config = AppConfiguration(
            applicationSupportDirectory: FileManager.default.temporaryDirectory,
            metaAppID: "app123"
        )
        let oauth = InstagramOAuthService(configuration: config, keychain: keychain, http: FixtureHTTPClient())
        let (_, session) = try await oauth.beginAuthorization()
        do {
            _ = try await oauth.completeWithCode("code", expectedState: "wrong")
            XCTFail("Expected invalid state")
        } catch let error as AppError {
            if case .authentication = error {
                // ok
            } else {
                XCTFail("Wrong error \(error)")
            }
        }
        XCTAssertEqual(session.state.isEmpty, false)
    }

    func testInsightsFixtureDecodingAndPersistence() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/api/instagram_insights.json")
        let data = try Data(contentsOf: fixtureURL)
        struct Envelope: Decodable { let data: [InsightMetricDTO] }
        let insights = try JSONDecoder().decode(Envelope.self, from: data).data
        XCTAssertEqual(insights.count, 2)

        let db = try DatabaseManager.inMemory()
        let repo = InstagramRepository(db: db)
        try repo.upsertAccount(InstagramAccountRecord(id: "acc", username: "fixture"))
        let engine = AnalyticsEngine(repository: repo)
        let observed = try engine.persistInsights(accountId: "acc", mediaId: nil, insights: insights, provenance: "fixture")
        XCTAssertEqual(observed.filter { $0.completeness == .complete }.count, 2)

        let report = try engine.buildReport(
            accountId: "acc",
            periodStart: Date().addingTimeInterval(-86400 * 7),
            periodEnd: Date().addingTimeInterval(86400),
            expectedMetrics: ["reach", "views", "likes"]
        )
        XCTAssertTrue(report.missingMetrics.contains("likes"))
        XCTAssertFalse(report.observedMetrics.contains(where: { $0.name == "likes" && $0.value != nil && $0.completeness == .complete }))
    }

    func testNonAdditiveAggregationRejected() throws {
        let db = try DatabaseManager.inMemory()
        let engine = AnalyticsEngine(repository: InstagramRepository(db: db))
        let metrics = [
            ObservedMetric(name: "reach", value: 10, period: "day", completeness: .complete, provenance: "t"),
            ObservedMetric(name: "reach", value: 20, period: "day", completeness: .complete, provenance: "t")
        ]
        XCTAssertThrowsError(try engine.aggregateAdditive(metrics: metrics, name: "reach"))
        let likes = [
            ObservedMetric(name: "likes", value: 10, period: "day", completeness: .complete, provenance: "t"),
            ObservedMetric(name: "likes", value: 5, period: "day", completeness: .complete, provenance: "t")
        ]
        XCTAssertEqual(try engine.aggregateAdditive(metrics: likes, name: "likes"), 15)
    }

    func testEmptyInsightsAreMissingNotZero() throws {
        let db = try DatabaseManager.inMemory()
        let repo = InstagramRepository(db: db)
        try repo.upsertAccount(InstagramAccountRecord(id: "acc", username: "u"))
        let engine = AnalyticsEngine(repository: repo)
        let observed = try engine.persistInsights(accountId: "acc", mediaId: nil, insights: [], provenance: "api")
        XCTAssertEqual(observed.first?.completeness, .missing)
        XCTAssertNil(observed.first?.value)
    }

    func testGraphClientFixture() async throws {
        let insights = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/api/instagram_insights.json"))
        let media = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/api/instagram_media.json"))
        let http = FixtureHTTPClient(handlers: [
            "insights": (insights, 200),
            "media": (media, 200),
            "me": (Data(#"{"id":"1","username":"u","account_type":"BUSINESS"}"#.utf8), 200)
        ])
        let client = InstagramGraphClient(configuration: AppConfiguration(), http: http) {
            "token"
        }
        let me = try await client.fetchMe()
        XCTAssertEqual(me.username, "u")
        let items = try await client.fetchMedia(userID: "1")
        XCTAssertEqual(items.count, 1)
        let metrics = try await client.fetchAccountInsights(userID: "1", metrics: ["reach", "views"])
        XCTAssertEqual(metrics.count, 2)
    }
}
