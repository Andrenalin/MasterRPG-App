// @copyright André Trettin

import Charts
import SwiftUI

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
                Text("\(byteCount.formatted(.byteCount(style: .file))) transferred", bundle: .module)
                    .font(.headline)
                Chart(points) { point in
                    BarMark(
                        x: .value(String(localized: "Transport", bundle: .module), point.title),
                        y: .value(String(localized: "Messages", bundle: .module), point.count)
                    )
                    .foregroundStyle(by: .value(String(localized: "Transport", bundle: .module), point.title))
                    .accessibilityLabel(point.title)
                    .accessibilityValue(Text("\(point.count) messages", bundle: .module))
                }
                .chartLegend(.hidden)
                .chartYScale(domain: .automatic(includesZero: true))
                .frame(minHeight: 240, maxHeight: 380)
            }
        }
    }
}

#Preview {
    let summary = GameStatisticsPreviewController().summary(
        referenceDate: GamePreviewData.referenceDate,
        calendar: GamePreviewData.calendar
    )
    GameStatisticsNetworkChart(points: summary.network, byteCount: summary.payloadByteCount)
        .padding()
}
