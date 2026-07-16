// @copyright André Trettin

import SwiftUI

struct GameStatisticsHighlightsView: View {
    let summary: GameStatisticsSummary

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
            GameStatisticsHighlightCard(
                title: String(localized: "Games", bundle: .module),
                value: summary.sessionCount.formatted(),
                systemImage: "person.3"
            )
            GameStatisticsHighlightCard(
                title: String(localized: "Play Time", bundle: .module),
                value: GameStatisticsFormat.duration(summary.totalDuration),
                systemImage: "clock"
            )
            GameStatisticsHighlightCard(
                title: String(localized: "Average", bundle: .module),
                value: GameStatisticsFormat.duration(summary.averageDuration),
                systemImage: "chart.bar"
            )
            GameStatisticsHighlightCard(
                title: String(localized: "Longest Game", bundle: .module),
                value: GameStatisticsFormat.duration(summary.longestDuration),
                systemImage: "trophy"
            )
            GameStatisticsHighlightCard(
                title: String(localized: "Dice Rolls", bundle: .module),
                value: summary.diceRollCount.formatted(),
                systemImage: "dice"
            )
            GameStatisticsHighlightCard(
                title: String(localized: "Criticals", bundle: .module),
                value: summary.criticalCount.formatted(),
                systemImage: "sparkles"
            )
        }
    }
}

#Preview {
    GameStatisticsHighlightsView(
        summary: GameStatisticsPreviewController().summary(
            referenceDate: GamePreviewData.referenceDate,
            calendar: GamePreviewData.calendar
        )
    )
    .padding()
}
