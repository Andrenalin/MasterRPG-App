// @copyright André Trettin

import CoreRPG
import SwiftUI

/// A dense, adaptive dashboard for players who want all setup context visible.
struct GuildHallStartGameView: View {
    let root: GameRoot
    @Binding var role: GameSetupRole
    let openStatistics: @MainActor () -> Void
    let openSupporter: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Guild Hall", bundle: .module)
                            .font(.largeTitle)
                            .bold()
                        Text("Your session dashboard", bundle: .module)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "building.columns.fill")
                        .font(.largeTitle)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        VStack {
                            SupporterWelcomeCard(openSupporter: openSupporter)
                            GameSetupSectionCard(
                                LocalizedStringResource("Role", bundle: .module),
                                systemImage: "person.crop.circle"
                            ) {
                                GameSetupRolePicker(selection: $role)
                            }
                            GameSetupStatisticsCard(
                                sessionCount: root.statisticsModel.summary.sessionCount,
                                openStatistics: openStatistics
                            )
                            GameSetupTipCard()
                        }
                        .containerRelativeFrame(.horizontal, count: 5, span: 2, spacing: 24)

                        GameSetupSectionCard(
                            LocalizedStringResource("Session setup", bundle: .module),
                            systemImage: role.systemImage
                        ) {
                            GameSetupRoleContent(root: root, selection: role)
                        }
                        .containerRelativeFrame(.horizontal, count: 5, span: 3, spacing: 24)
                    }

                    VStack {
                        SupporterWelcomeCard(openSupporter: openSupporter)
                        GameSetupRolePicker(selection: $role)
                        GameSetupSectionCard(
                            LocalizedStringResource("Session setup", bundle: .module),
                            systemImage: role.systemImage
                        ) {
                            GameSetupRoleContent(root: root, selection: role)
                        }
                        GameSetupStatisticsCard(
                            sessionCount: root.statisticsModel.summary.sessionCount,
                            openStatistics: openStatistics
                        )
                        GameSetupTipCard()
                    }
                }
            }
            .frame(maxWidth: 1100)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background { GameSetupBackdrop() }
        .moduleTint(.game)
    }
}

#Preview("2 · Guild Hall", traits: .mockData) {
    @Previewable @State var role = GameSetupRole.previewMaster

    ManagedNavigationStack {
        GuildHallStartGameView(
            root: .preview,
            role: $role,
            openStatistics: {},
            openSupporter: {}
        )
    }
    .environment(\.supporterTier, .silver)
}
