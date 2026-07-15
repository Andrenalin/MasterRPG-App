// @copyright André Trettin

import Charts
import SwiftUI

struct GameStatisticsActivityChart: View {
    let points: [GameStatisticTimePoint]
    let metric: GameStatisticsMetric
    @State private var selectedDate: Date?

    var body: some View {
        GameStatisticsChartCard(
            title: String(localized: "Activity", bundle: .module),
            systemImage: "chart.xyaxis.line"
        ) {
            if points.isEmpty {
                GameStatisticsNoChartDataView()
            } else {
                Chart(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value(metric.title, point.value(for: metric))
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue.opacity(0.35), .blue.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(metric.title, point.value(for: metric))
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)

                    if let selectedDate,
                       Calendar.autoupdatingCurrent.isDate(point.date, inSameDayAs: selectedDate) {
                        PointMark(
                            x: .value("Selected Date", point.date),
                            y: .value(metric.title, point.value(for: metric))
                        )
                        .foregroundStyle(.primary)
                        .symbolSize(80)
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            GameStatisticsSelectionLabel(
                                title: point.date.formatted(date: .abbreviated, time: .omitted),
                                value: metric == .duration
                                    ? GameStatisticsFormat.duration(point.duration)
                                    : point.sessionCount.formatted()
                            )
                        }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 60 * 60 * 24 * 90)
                .chartYAxisLabel(metric.title)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(minHeight: 260, maxHeight: 420)
                .accessibilityLabel(Text("Game activity over time", bundle: .module))
            }
        }
    }
}

struct GameStatisticsScheduleChart: View {
    let points: [GameStatisticHeatMapPoint]

    var body: some View {
        GameStatisticsChartCard(
            title: String(localized: "When You Play", bundle: .module),
            systemImage: "calendar"
        ) {
            if points.isEmpty {
                GameStatisticsNoChartDataView()
            } else {
                Chart(points) { point in
                    RectangleMark(
                        x: .value("Hour", point.hour),
                        y: .value("Weekday", weekdayTitle(for: point.weekday))
                    )
                    .foregroundStyle(by: .value("Hours Played", point.duration / 3_600))
                    .accessibilityLabel("\(weekdayTitle(for: point.weekday)), \(point.hour.formatted())")
                    .accessibilityValue(GameStatisticsFormat.duration(point.duration))
                }
                .chartXScale(domain: 0...23)
                .chartXAxis {
                    AxisMarks(values: [0, 4, 8, 12, 16, 20, 23])
                }
                .chartForegroundStyleScale(range: Gradient(colors: [.blue.opacity(0.15), .cyan, .indigo]))
                .chartLegend(position: .bottom)
                .frame(minHeight: 280, maxHeight: 440)
                .accessibilityLabel(Text("Play time by weekday and hour", bundle: .module))
            }
        }
    }

    private func weekdayTitle(for weekday: Int) -> String {
        let symbols = Calendar.autoupdatingCurrent.shortWeekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return weekday.formatted() }
        return symbols[weekday - 1]
    }
}

struct GameStatisticsCategoryBarChart: View {
    let section: GameStatisticsSection
    let points: [GameStatisticCategoryPoint]
    let metric: GameStatisticsMetric

    var body: some View {
        GameStatisticsChartCard(title: section.title, systemImage: section.systemImage) {
            if points.isEmpty {
                GameStatisticsNoChartDataView()
            } else {
                Chart(points.prefix(8)) { point in
                    BarMark(
                        x: .value(metric.title, point.value(for: metric)),
                        y: .value("Category", point.title)
                    )
                    .foregroundStyle(by: .value("Category", point.title))
                    .accessibilityLabel(point.title)
                    .accessibilityValue(
                        metric == .duration
                            ? GameStatisticsFormat.duration(point.value)
                            : point.count.formatted()
                    )
                }
                .chartLegend(.hidden)
                .chartXAxisLabel(metric.title)
                .chartXScale(domain: .automatic(includesZero: true))
                .frame(minHeight: 260, maxHeight: 460)
            }
        }
    }
}

struct GameStatisticsCountBarChart: View {
    let section: GameStatisticsSection
    let points: [GameStatisticCategoryPoint]

    var body: some View {
        GameStatisticsChartCard(title: section.title, systemImage: section.systemImage) {
            if points.isEmpty {
                GameStatisticsNoChartDataView()
            } else {
                Chart(points.prefix(8)) { point in
                    BarMark(
                        x: .value("Content Type", point.title),
                        y: .value("Shared Items", point.count)
                    )
                    .foregroundStyle(by: .value("Content Type", point.title))
                    .accessibilityLabel(point.title)
                    .accessibilityValue("\(point.count.formatted()) shared items")
                }
                .chartLegend(position: .bottom)
                .chartYScale(domain: .automatic(includesZero: true))
                .frame(minHeight: 260, maxHeight: 440)
            }
        }
    }
}

struct GameStatisticsDiceChart: View {
    let points: [GameStatisticCategoryPoint]
    @State private var selectedAngle: Double?

    var body: some View {
        GameStatisticsChartCard(
            title: String(localized: "Dice", bundle: .module),
            systemImage: "dice"
        ) {
            if points.isEmpty {
                GameStatisticsNoChartDataView()
            } else {
                Chart(points) { point in
                    SectorMark(
                        angle: .value("Rolls", point.count),
                        innerRadius: .ratio(0.62),
                        outerRadius: .inset(selectedPoint?.id == point.id ? 0 : 8),
                        angularInset: 1.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(by: .value("Result", point.title))
                    .opacity(selectedPoint == nil || selectedPoint?.id == point.id ? 1 : 0.4)
                    .accessibilityLabel(point.title)
                    .accessibilityValue("\(point.count.formatted()) rolls")
                }
                .chartAngleSelection(value: $selectedAngle)
                .chartLegend(position: .bottom)
                .chartBackground { _ in
                    VStack {
                        Text(selectedPoint?.title ?? String(localized: "Total", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text((selectedPoint?.count ?? total).formatted())
                            .font(.title2)
                            .bold()
                    }
                }
                .frame(minHeight: 280, maxHeight: 420)
            }
        }
    }

    private var total: Int {
        points.reduce(0) { $0 + $1.count }
    }

    private var selectedPoint: GameStatisticCategoryPoint? {
        guard let selectedAngle else { return nil }
        var runningTotal = 0.0
        return points.first { point in
            let end = runningTotal + Double(point.count)
            defer { runningTotal = end }
            return (runningTotal..<end).contains(selectedAngle)
        }
    }
}

struct GameStatisticsNetworkChart: View {
    let points: [GameStatisticCategoryPoint]
    let byteCount: Int64

    var body: some View {
        GameStatisticsChartCard(
            title: String(localized: "Connection", bundle: .module),
            systemImage: "network"
        ) {
            if points.isEmpty {
                GameStatisticsNoChartDataView()
            } else {
                Text("\(byteCount.formatted(.byteCount(style: .file))) transferred")
                    .font(.headline)
                Chart(points) { point in
                    BarMark(
                        x: .value("Transport", point.title),
                        y: .value("Messages", point.count)
                    )
                    .foregroundStyle(by: .value("Transport", point.title))
                    .accessibilityLabel(point.title)
                    .accessibilityValue("\(point.count.formatted()) messages")
                }
                .chartLegend(.hidden)
                .chartYScale(domain: .automatic(includesZero: true))
                .frame(minHeight: 240, maxHeight: 380)
            }
        }
    }
}

private struct GameStatisticsSelectionLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .bold()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.thickMaterial, in: .rect(cornerRadius: 10))
    }
}

struct GameStatisticsNoChartDataView: View {
    var body: some View {
        Label {
            Text("No data for this selection", bundle: .module)
        } icon: {
            Image(systemName: "chart.bar.xaxis")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}
