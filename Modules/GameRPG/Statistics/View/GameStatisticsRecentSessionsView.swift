// @copyright André Trettin

import SwiftUI

struct GameStatisticsRecentSessionsView: View {
    let sessions: [GameStatisticSessionSnapshot]
    @Bindable var model: GameStatisticsModel

    var body: some View {
        GameStatisticsChartCard(
            title: String(localized: "Recent Games", bundle: .module),
            systemImage: "clock.arrow.circlepath"
        ) {
            LazyVStack {
                ForEach(sessions) { session in
                    NavigationLink {
                        GameStatisticsSessionDetailView(session: session, model: model)
                    } label: {
                        GameStatisticsSessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }
}

#Preview {
    let model = GameStatisticsModel.previewFixture()
    NavigationStack {
        GameStatisticsRecentSessionsView(sessions: model.summary.recentSessions, model: model)
    }
    .padding()
}
