// @copyright André Trettin

import Charts
import SwiftUI

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
                        x: .value(String(localized: "Content Type", bundle: .module), point.title),
                        y: .value(String(localized: "Shared Items", bundle: .module), point.count)
                    )
                    .foregroundStyle(by: .value(String(localized: "Content Type", bundle: .module), point.title))
                    .accessibilityLabel(point.title)
                    .accessibilityValue(Text("\(point.count) shared items", bundle: .module))
                }
                .chartLegend(position: .bottom)
                .chartYScale(domain: .automatic(includesZero: true))
                .frame(minHeight: 260, maxHeight: 440)
            }
        }
    }
}

#Preview {
    let summary = GameStatisticsPreviewController().summary(
        referenceDate: GamePreviewData.referenceDate,
        calendar: GamePreviewData.calendar
    )
    GameStatisticsCountBarChart(section: .sharedContent, points: summary.modules)
        .padding()
}
