// @copyright André Trettin

import SwiftUI

struct GameStatisticsSectionView: View {
    let section: GameStatisticsSection
    let summary: GameStatisticsSummary
    let metric: GameStatisticsMetric

    var body: some View {
        switch section {
        case .activity:
            GameStatisticsActivityChart(points: summary.activity, metric: metric)
        case .schedule:
            GameStatisticsScheduleChart(points: summary.schedule)
        case .roles:
            GameStatisticsCategoryBarChart(section: section, points: summary.roles, metric: metric)
        case .characters:
            GameStatisticsCategoryBarChart(section: section, points: summary.characters, metric: metric)
        case .adventures:
            GameStatisticsCategoryBarChart(section: section, points: summary.adventures, metric: metric)
        case .dice:
            GameStatisticsDiceChart(points: summary.diceOutcomes)
        case .sharedContent:
            GameStatisticsCountBarChart(section: section, points: summary.modules)
        case .party:
            GameStatisticsCategoryBarChart(section: section, points: summary.party, metric: metric)
        case .network:
            GameStatisticsNetworkChart(points: summary.network, byteCount: summary.payloadByteCount)
        }
    }
}

#Preview {
    GameStatisticsSectionView(
        section: .dice,
        summary: GameStatisticsPreviewController().summary(
            referenceDate: GamePreviewData.referenceDate,
            calendar: GamePreviewData.calendar
        ),
        metric: .duration
    )
    .padding()
}
