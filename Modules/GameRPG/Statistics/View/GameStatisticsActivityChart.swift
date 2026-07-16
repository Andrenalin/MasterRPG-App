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
                        x: .value(String(localized: "Date", bundle: .module), point.date),
                        y: .value(metric.title, point.value(for: metric))
                    )
                    .accessibilityHidden(true)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.blue.opacity(0.35), .blue.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value(String(localized: "Date", bundle: .module), point.date),
                        y: .value(metric.title, point.value(for: metric))
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
                    .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue(
                        metric == .duration
                            ? GameStatisticsFormat.duration(point.duration)
                            : point.sessionCount.formatted()
                    )

                    if let selectedDate,
                       Calendar.autoupdatingCurrent.isDate(point.date, inSameDayAs: selectedDate) {
                        PointMark(
                            x: .value(String(localized: "Selected Date", bundle: .module), point.date),
                            y: .value(metric.title, point.value(for: metric))
                        )
                        .foregroundStyle(.primary)
                        .symbolSize(80)
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                        ) {
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

#Preview {
    let summary = GameStatisticsPreviewController().summary(
        referenceDate: GamePreviewData.referenceDate,
        calendar: GamePreviewData.calendar
    )
    GameStatisticsActivityChart(points: summary.activity, metric: .duration)
        .padding()
}
