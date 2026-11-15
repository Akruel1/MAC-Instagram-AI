import SwiftUI
import Charts
import DesignSystem
import Instagram

struct AnalyticsView: View {
    @Bindable var model: AppModel
    @Environment(\.studioPalette) private var palette

    var body: some View {
        ContentColumn(maxWidth: 920) {
            WorkspaceHeader(
                title: "Analytics",
                status: model.instagramConnected ? "Observed metrics only" : "Instagram not connected",
                statusColor: model.instagramConnected ? palette.success : palette.warning
            ) {
                HStack(spacing: 8) {
                    Picker("Range", selection: $model.analyticsDays) {
                        Text("7d").tag(7)
                        Text("14d").tag(14)
                        Text("30d").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .onChange(of: model.analyticsDays) { _, _ in
                        Task { await model.loadAnalytics() }
                    }

                    StudioToolbarButton("Sync", systemImage: "arrow.triangle.2.circlepath", isEnabled: model.instagramConnected) {
                        Task { await model.syncAnalytics() }
                    }
                    StudioToolbarButton("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.loadAnalytics() }
                    }
                }
            }

            if model.analyticsLoading {
                ProgressView().controlSize(.small)
            }

            if let note = model.analyticsNote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.bottom, StudioSpace.md)
            }

            if !model.instagramConnected {
                empty("Connect Instagram to sync metrics", "Analytics never invents reach, likes, or rankings.")
            } else if let report = model.analyticsReport {
                metricsGrid(report)
                if !report.observedMetrics.filter({ $0.value != nil }).isEmpty {
                    chart(report)
                        .padding(.top, StudioSpace.lg)
                }
                ranking(report)
                    .padding(.top, StudioSpace.lg)
            } else {
                empty("No report yet", "Sync when credentials allow, or wait until metrics are persisted locally.")
            }
        }
        .background(palette.bgBase)
        .task { await model.loadAnalytics() }
    }

    private func empty(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Text(message).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
        .padding(.vertical, StudioSpace.md)
    }

    private func metricsGrid(_ report: AnalyticsReport) -> some View {
        let complete = report.observedMetrics.filter { $0.completeness == .complete && $0.value != nil }
        return VStack(alignment: .leading, spacing: StudioSpace.sm) {
            StudioSectionLabel("Observed")
            if complete.isEmpty {
                Text("No complete metrics in this period.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(complete.prefix(6), id: \.name) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.name)
                                .font(StudioType.caption)
                                .foregroundStyle(palette.textTertiary)
                            Text(format(metric.value))
                                .font(StudioType.metric)
                                .foregroundStyle(palette.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(palette.bgElevated))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 0.5))
                    }
                }
            }
            if !report.missingMetrics.isEmpty {
                Text("Missing: \(report.missingMetrics.joined(separator: ", "))")
                    .font(StudioType.caption)
                    .foregroundStyle(palette.warning)
            }
        }
    }

    private func chart(_ report: AnalyticsReport) -> some View {
        let points = report.observedMetrics.filter { $0.value != nil }.prefix(8)
        return VStack(alignment: .leading, spacing: StudioSpace.sm) {
            StudioSectionLabel("Distribution")
            Chart(Array(points), id: \.name) { metric in
                BarMark(
                    x: .value("Metric", metric.name),
                    y: .value("Value", metric.value ?? 0)
                )
                .foregroundStyle(palette.accent)
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 9))
                }
            }
        }
    }

    private func ranking(_ report: AnalyticsReport) -> some View {
        VStack(alignment: .leading, spacing: StudioSpace.sm) {
            StudioSectionLabel("Media ranking")
            if report.mediaRanking.isEmpty {
                Text("No ranked media with observed scores.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(report.mediaRanking.prefix(8), id: \.mediaId) { item in
                    HStack {
                        Text(item.mediaId)
                            .font(StudioType.mono)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text(item.score.map { String(format: "%.1f", $0) } ?? "—")
                            .font(StudioType.timecode)
                            .foregroundStyle(palette.textPrimary)
                    }
                    .padding(.vertical, 4)
                }
                Text(report.mediaRanking.first?.scoreBasis ?? "")
                    .font(StudioType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 1000 { return String(format: "%.1fk", value / 1000) }
        return String(format: "%.0f", value)
    }
}
