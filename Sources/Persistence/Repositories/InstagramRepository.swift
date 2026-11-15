import Foundation
import GRDB
import Core

public struct InstagramAccountRecord: Sendable, Equatable, Codable {
    public var id: String
    public var username: String
    public var accountType: String?
    public var linkedAt: Date

    public init(id: String, username: String, accountType: String? = nil, linkedAt: Date = Date()) {
        self.id = id
        self.username = username
        self.accountType = accountType
        self.linkedAt = linkedAt
    }
}

public struct InstagramMediaRecord: Sendable, Equatable, Codable {
    public var id: String
    public var accountId: String
    public var mediaType: String
    public var caption: String?
    public var permalink: String?
    public var publishedAt: Date?
    public var fetchedAt: Date

    public init(
        id: String,
        accountId: String,
        mediaType: String,
        caption: String? = nil,
        permalink: String? = nil,
        publishedAt: Date? = nil,
        fetchedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.mediaType = mediaType
        self.caption = caption
        self.permalink = permalink
        self.publishedAt = publishedAt
        self.fetchedAt = fetchedAt
    }
}

public enum MetricCompleteness: String, Sendable, Codable, Equatable {
    case complete
    case partial
    case missing
    case unavailable
}

public struct InstagramMetricRecord: Sendable, Equatable, Codable {
    public var id: String
    public var accountId: String?
    public var mediaId: String?
    public var metricName: String
    public var metricValue: Double?
    public var period: String
    public var observedAt: Date
    public var reportingStart: Date?
    public var reportingEnd: Date?
    public var provenance: String
    public var completeness: MetricCompleteness

    public init(
        id: String = UUID().uuidString,
        accountId: String? = nil,
        mediaId: String? = nil,
        metricName: String,
        metricValue: Double?,
        period: String,
        observedAt: Date = Date(),
        reportingStart: Date? = nil,
        reportingEnd: Date? = nil,
        provenance: String,
        completeness: MetricCompleteness
    ) {
        self.id = id
        self.accountId = accountId
        self.mediaId = mediaId
        self.metricName = metricName
        self.metricValue = metricValue
        self.period = period
        self.observedAt = observedAt
        self.reportingStart = reportingStart
        self.reportingEnd = reportingEnd
        self.provenance = provenance
        self.completeness = completeness
    }
}

public struct InstagramRepository: Sendable {
    private let dbQueue: DatabaseQueue

    public init(db: DatabaseManager) {
        self.dbQueue = db.dbQueue
    }

    public func upsertAccount(_ account: InstagramAccountRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO instagram_accounts (id, username, account_type, linked_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET username = excluded.username, account_type = excluded.account_type
                """,
                arguments: [account.id, account.username, account.accountType, account.linkedAt]
            )
        }
    }

    public func upsertMedia(_ media: InstagramMediaRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO instagram_media (id, account_id, media_type, caption, permalink, published_at, fetched_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  media_type = excluded.media_type,
                  caption = excluded.caption,
                  permalink = excluded.permalink,
                  published_at = excluded.published_at,
                  fetched_at = excluded.fetched_at
                """,
                arguments: [
                    media.id, media.accountId, media.mediaType, media.caption,
                    media.permalink, media.publishedAt, media.fetchedAt
                ]
            )
        }
    }

    public func insertMetric(_ metric: InstagramMetricRecord) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO instagram_metrics (
                  id, account_id, media_id, metric_name, metric_value, period,
                  observed_at, reporting_start, reporting_end, provenance, completeness
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    metric.id, metric.accountId, metric.mediaId, metric.metricName, metric.metricValue,
                    metric.period, metric.observedAt, metric.reportingStart, metric.reportingEnd,
                    metric.provenance, metric.completeness.rawValue
                ]
            )
        }
    }

    public func metrics(accountId: String, since: Date?, until: Date?) throws -> [InstagramMetricRecord] {
        try dbQueue.read { db in
            var sql = "SELECT * FROM instagram_metrics WHERE account_id = ?"
            var args: [any DatabaseValueConvertible] = [accountId]
            if let since {
                sql += " AND observed_at >= ?"
                args.append(since)
            }
            if let until {
                sql += " AND observed_at <= ?"
                args.append(until)
            }
            sql += " ORDER BY observed_at ASC"
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map { row in
                InstagramMetricRecord(
                    id: row["id"],
                    accountId: row["account_id"],
                    mediaId: row["media_id"],
                    metricName: row["metric_name"],
                    metricValue: row["metric_value"],
                    period: row["period"],
                    observedAt: row["observed_at"],
                    reportingStart: row["reporting_start"],
                    reportingEnd: row["reporting_end"],
                    provenance: row["provenance"],
                    completeness: MetricCompleteness(rawValue: row["completeness"]) ?? .missing
                )
            }
        }
    }

    public func media(accountId: String) throws -> [InstagramMediaRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM instagram_media WHERE account_id = ? ORDER BY published_at DESC",
                arguments: [accountId]
            )
            return rows.map { row in
                InstagramMediaRecord(
                    id: row["id"],
                    accountId: row["account_id"],
                    mediaType: row["media_type"],
                    caption: row["caption"],
                    permalink: row["permalink"],
                    publishedAt: row["published_at"],
                    fetchedAt: row["fetched_at"]
                )
            }
        }
    }
}
