// @copyright André Trettin

import SwiftUI

struct GameStatisticsPreviewSessionsView: View {
    let sessions: [GameStatisticSessionSnapshot]

    var body: some View {
        GameStatisticsChartCard(
            title: String(localized: "Example Games", bundle: .module),
            systemImage: "clock.arrow.circlepath"
        ) {
            LazyVStack {
                ForEach(sessions) { session in
                    GameStatisticsSessionRow(session: session, showsDisclosureIndicator: false)
                    Divider()
                }
            }
        }
    }
}

#Preview {
    GameStatisticsPreviewSessionsView(
        sessions: GameStatisticsPreviewController().summary(
            referenceDate: GamePreviewData.referenceDate,
            calendar: GamePreviewData.calendar
        ).recentSessions
    )
    .padding()
}
