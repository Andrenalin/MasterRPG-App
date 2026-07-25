// @copyright André Trettin

import CoreRPG
import SwiftUI

/// A returning-player layout that foregrounds continuity and fast launch.
struct SessionChronicleStartGameView: View {
    let root: GameRoot
    @Binding var role: GameSetupRole
    let openStatistics: @MainActor () -> Void
    let openSupporter: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Session Chronicle", bundle: .module)
                            .font(.largeTitle)
                            .bold()
                        Text("Return to the table", bundle: .module)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "book.closed.fill")
                        .font(.largeTitle)
                }

                SupporterWelcomeCard(openSupporter: openSupporter)

                GameSetupSectionCard(
                    LocalizedStringResource("Continue as", bundle: .module),
                    systemImage: "clock.arrow.circlepath"
                ) {
                    GameSetupRolePicker(selection: $role)
                    Label {
                        Text(role.subtitle)
                    } icon: {
                        Image(systemName: role.systemImage)
                    }
                    .foregroundStyle(.secondary)
                }

                GameSetupSectionCard(
                    LocalizedStringResource("Last setup", bundle: .module),
                    systemImage: "bookmark.fill"
                ) {
                    GameSetupRoleContent(root: root, selection: role)
                }

                GameSetupSectionCard(
                    LocalizedStringResource("Chronicle", bundle: .module),
                    systemImage: "chart.line.uptrend.xyaxis"
                ) {
                    GameSetupStatisticsCard(
                        sessionCount: root.statisticsModel.summary.sessionCount,
                        openStatistics: openStatistics
                    )
                    GameSetupTipCard()
                }
            }
            .frame(maxWidth: 860)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background { GameSetupBackdrop() }
        .moduleTint(.game)
    }
}

#Preview("5 · Session Chronicle", traits: .mockData) {
    @Previewable @State var role: GameSetupRole = .player

    ManagedNavigationStack {
        SessionChronicleStartGameView(
            root: .preview,
            role: $role,
            openStatistics: {},
            openSupporter: {}
        )
    }
    .environment(\.supporterTier, .gold)
}
