// @copyright André Trettin

import Charts
import SwiftUI

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
                        y: .value(String(localized: "Category", bundle: .module), point.title)
                    )
                    .foregroundStyle(by: .value(String(localized: "Category", bundle: .module), point.title))
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

#Preview {
    let summary = GameStatisticsPreviewController().summary(
        referenceDate: GamePreviewData.referenceDate,
        calendar: GamePreviewData.calendar
    )
    GameStatisticsCategoryBarChart(section: .characters, points: summary.characters, metric: .duration)
        .padding()
}
