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
                    GameStatisticsSessionRow(session: session)
                    Divider()
                }
                NavigationLink {
                    GameStatisticsAllSessionsView(model: model)
                } label: {
                    Label {
                        Text("Show All Games", bundle: .module)
                    } icon: {
                        Image(systemName: "list.bullet")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
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
