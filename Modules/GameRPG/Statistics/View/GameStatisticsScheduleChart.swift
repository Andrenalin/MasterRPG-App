// @copyright André Trettin

import Charts
import SwiftUI

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
                        x: .value(String(localized: "Hour", bundle: .module), point.hour),
                        y: .value(String(localized: "Weekday", bundle: .module), weekdayTitle(for: point.weekday))
                    )
                    .foregroundStyle(by: .value(String(localized: "Hours Played", bundle: .module), point.duration / 3_600))
                    .accessibilityLabel(
                        Text(
                            "\(weekdayTitle(for: point.weekday)), \(point.hour.formatted())",
                            bundle: .module
                        )
                    )
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

#Preview {
    let summary = GameStatisticsPreviewController().summary(
        referenceDate: GamePreviewData.referenceDate,
        calendar: GamePreviewData.calendar
    )
    GameStatisticsScheduleChart(points: summary.schedule)
        .padding()
}
