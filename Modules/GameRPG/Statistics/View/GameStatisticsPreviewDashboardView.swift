// @copyright André Trettin

import SwiftUI

struct GameStatisticsPreviewDashboardView: View {
    private let previewSections: [GameStatisticsSection] = [
        .activity, .characters, .dice, .sharedContent
    ]
    private let additionalSections: [GameStatisticsSection] = [
        .schedule, .roles, .adventures, .party, .network
    ]

    let summary: GameStatisticsSummary
    let collectionEnabled: Bool

    var body: some View {
        VStack {
            GameStatisticsPreviewHeader(collectionEnabled: collectionEnabled)
            GameStatisticsHighlightsView(summary: summary)

            ForEach(previewSections) { section in
                GameStatisticsSectionView(section: section, summary: summary, metric: .duration)
            }

            GameStatisticsPreviewSessionsView(sessions: summary.recentSessions)

            GameStatisticsChartCard(
                title: String(localized: "More Insights", bundle: .module),
                systemImage: "sparkles"
            ) {
                Text("Completed games can also reveal these patterns.", bundle: .module)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) {
                    ForEach(additionalSections) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.quaternary, in: .rect(cornerRadius: 14))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    GameStatisticsPreviewDashboardView(
        summary: GameStatisticsPreviewController().summary(
            referenceDate: GamePreviewData.referenceDate,
            calendar: GamePreviewData.calendar
        ),
        collectionEnabled: true
    )
    .padding()
}
