import Foundation
import Core
import Persistence

public struct ObservedMetric: Sendable, Equatable, Codable {
    public var name: String
    public var value: Double?
    public var period: String
    public var completeness: MetricCompleteness
    public var provenance: String
    public var mediaId: String?
    public var observedAt: Date

    public init(
        name: String,
        value: Double?,
        period: String,
        completeness: MetricCompleteness,
        provenance: String,
        mediaId: String? = nil,
        observedAt: Date = Date()
    ) {
        self.name = name
        self.value = value
        self.period = period
        self.completeness = completeness
        self.provenance = provenance
        self.mediaId = mediaId
        self.observedAt = observedAt
    }
}

public struct AnalyticsReport: Sendable, Equatable, Codable {
    public var accountId: String
    public var periodStart: Date
    public var periodEnd: Date
    public var observedMetrics: [ObservedMetric]
    public var missingMetrics: [String]
    public var mediaRanking: [MediaPerformance]
    public var interpretationsAllowed: Bool
    public var generatedAt: Date
    public var dataFreshnessHours: Double?

    public init(
        accountId: String,
        periodStart: Date,
        periodEnd: Date,
        observedMetrics: [ObservedMetric],
        missingMetrics: [String],
        mediaRanking: [MediaPerformance],
        interpretationsAllowed: Bool = true,
        generatedAt: Date = Date(),
        dataFreshnessHours: Double? = nil
    ) {
        self.accountId = accountId
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.observedMetrics = observedMetrics
        self.missingMetrics = missingMetrics
        self.mediaRanking = mediaRanking
        self.interpretationsAllowed = interpretationsAllowed
        self.generatedAt = generatedAt
        self.dataFreshnessHours = dataFreshnessHours
    }
}

public struct MediaPerformance: Sendable, Equatable, Codable {
    public var mediaId: String
    public var mediaType: String
    public var score: Double?
    public var metrics: [ObservedMetric]
    public var scoreBasis: String
}

/// Non-additive metrics must never be summed across periods/media.
public enum MetricSemantics: Sendable {
    public static let nonAdditive: Set<String> = [
        "reach", "accounts_engaged", "profile_views", "follower_count", "online_followers"
    ]

    public static let additive: Set<String> = [
        "likes", "comments", "saves", "shares", "views", "impressions", "total_interactions"
    ]

    public static func canSum(_ name: String) -> Bool {
        additive.contains(name.lowercased()) && !nonAdditive.contains(name.lowercased())
    }
}

public struct AnalyticsEngine: Sendable {
    private let repository: InstagramRepository

    public init(repository: InstagramRepository) {
        self.repository = repository
    }

    public func persistInsights(
        accountId: String,
        mediaId: String?,
        insights: [InsightMetricDTO],
        provenance: String
    ) throws -> [ObservedMetric] {
        var observed: [ObservedMetric] = []
        if insights.isEmpty {
            return [
                ObservedMetric(
                    name: "_empty_insights_payload",
                    value: nil,
                    period: "n/a",
                    completeness: .missing,
                    provenance: provenance,
                    mediaId: mediaId
                )
            ]
        }
        for insight in insights {
            let value = insight.values.last?.value
            let completeness: MetricCompleteness
            if insight.values.isEmpty {
                completeness = .missing
            } else if value == nil {
                completeness = .unavailable
            } else {
                completeness = .complete
            }
            let record = InstagramMetricRecord(
                accountId: accountId,
                mediaId: mediaId,
                metricName: insight.name,
                metricValue: value,
                period: insight.period,
                provenance: provenance,
                completeness: completeness
            )
            try repository.insertMetric(record)
            observed.append(
                ObservedMetric(
                    name: insight.name,
                    value: value,
                    period: insight.period,
                    completeness: completeness,
                    provenance: provenance,
                    mediaId: mediaId
                )
            )
        }
        return observed
    }

    public func buildReport(
        accountId: String,
        periodStart: Date,
        periodEnd: Date,
        expectedMetrics: [String]
    ) throws -> AnalyticsReport {
        let metrics = try repository.metrics(accountId: accountId, since: periodStart, until: periodEnd)
        let observed = metrics.map {
            ObservedMetric(
                name: $0.metricName,
                value: $0.metricValue,
                period: $0.period,
                completeness: $0.completeness,
                provenance: $0.provenance,
                mediaId: $0.mediaId,
                observedAt: $0.observedAt
            )
        }
        let present = Set(observed.filter { $0.completeness == .complete }.map(\.name))
        let missing = expectedMetrics.filter { !present.contains($0) }
        let media = try repository.media(accountId: accountId)
        let ranking = rankMedia(media: media, metrics: observed)
        let freshest = observed.map(\.observedAt).max()
        let freshness = freshest.map { Date().timeIntervalSince($0) / 3600 }

        return AnalyticsReport(
            accountId: accountId,
            periodStart: periodStart,
            periodEnd: periodEnd,
            observedMetrics: observed,
            missingMetrics: missing,
            mediaRanking: ranking,
            dataFreshnessHours: freshness
        )
    }

    public func aggregateAdditive(metrics: [ObservedMetric], name: String) throws -> Double? {
        guard MetricSemantics.canSum(name) else {
            throw AppError.validation("Metric \(name) is non-additive and cannot be summed")
        }
        let values = metrics.filter { $0.name == name && $0.completeness == .complete }.compactMap(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    public func periodComparison(
        current: [ObservedMetric],
        previous: [ObservedMetric],
        metric: String
    ) -> (current: Double?, previous: Double?, delta: Double?) {
        let c = current.first(where: { $0.name == metric && $0.completeness == .complete })?.value
        let p = previous.first(where: { $0.name == metric && $0.completeness == .complete })?.value
        let delta: Double?
        if let c, let p { delta = c - p } else { delta = nil }
        return (c, p, delta)
    }

    private func rankMedia(media: [InstagramMediaRecord], metrics: [ObservedMetric]) -> [MediaPerformance] {
        media.map { item in
            let related = metrics.filter { $0.mediaId == item.id }
            // Prefer additive engagement signals when present; never invent values.
            let likes = related.first(where: { $0.name == "likes" })?.value
            let comments = related.first(where: { $0.name == "comments" })?.value
            let views = related.first(where: { $0.name == "views" })?.value
            let score: Double?
            if likes != nil || comments != nil || views != nil {
                score = (likes ?? 0) + (comments ?? 0) + ((views ?? 0) * 0.01)
            } else {
                score = nil
            }
            return MediaPerformance(
                mediaId: item.id,
                mediaType: item.mediaType,
                score: score,
                metrics: related,
                scoreBasis: "likes+comments+0.01*views (observed only; nil if none present)"
            )
        }
        .sorted { ($0.score ?? -1) > ($1.score ?? -1) }
    }
}
