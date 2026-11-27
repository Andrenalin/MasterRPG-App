// @copyright André Trettin

import Charts
import SwiftUI

struct GameStatisticsDiceChart: View {
    let points: [GameStatisticCategoryPoint]
    @State private var selectedAngle: Double?

    var body: some View {
        GameStatisticsChartCard(
            title: String(localized: "Dice", bundle: .module),
            systemImage: "dice"
        ) {
            if chartPoints.isEmpty {
                GameStatisticsNoChartDataView()
            } else {
                Chart(chartPoints) { point in
                    SectorMark(
                        angle: .value(String(localized: "Rolls", bundle: .module), point.count),
                        innerRadius: .ratio(0.62),
                        outerRadius: .inset(selectedPoint?.id == point.id ? 0 : 8),
                        angularInset: 1.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(by: .value(String(localized: "Result", bundle: .module), point.title))
                    .opacity(selectedPoint == nil || selectedPoint?.id == point.id ? 1 : 0.4)
                    .accessibilityLabel(point.title)
                    .accessibilityValue(Text("\(point.count) rolls", bundle: .module))
                }
                .chartAngleSelection(value: $selectedAngle)
                .chartLegend(position: .bottom)
                .chartPlotStyle { plotArea in
                    // Centered in the plot area itself (the legend sits below it), without a
                    // GeometryReader resolving the plot frame. See CODE_AUDIT_29 §4.4.
                    plotArea.overlay {
                        VStack {
                            Text(selectedPoint?.title ?? String(localized: "Total", bundle: .module))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text((selectedPoint?.count ?? total).formatted())
                                .font(.title2)
                                .bold()
                        }
                        // The plot area carries the first series' colour as its foreground
                        // style; without this the total was drawn in the "Rolled" blue.
                        .foregroundStyle(Color.primary)
                    }
                }
                .frame(minHeight: 280, maxHeight: 420)
            }
        }
    }

    private var chartPoints: [GameStatisticCategoryPoint] {
        points.filter { $0.count > 0 }
    }

    private var total: Int {
        chartPoints.reduce(0) { $0 + $1.count }
    }

    private var selectedPoint: GameStatisticCategoryPoint? {
        guard let selectedAngle else { return nil }
        var runningTotal = 0.0
        return chartPoints.first { point in
            let end = runningTotal + Double(point.count)
            defer { runningTotal = end }
            return (runningTotal..<end).contains(selectedAngle)
        }
    }
}

#Preview {
    let summary = GameStatisticsPreviewController().summary(
        referenceDate: GamePreviewData.referenceDate,
        calendar: GamePreviewData.calendar
    )
    GameStatisticsDiceChart(points: summary.diceOutcomes)
        .padding()
}
