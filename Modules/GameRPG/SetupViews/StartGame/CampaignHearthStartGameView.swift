// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Warm, guided setup with the current session action at the center.
struct CampaignHearthStartGameView: View {
    let root: GameRoot
    @Binding var role: GameSetupRole
    let openStatistics: @MainActor () -> Void
    let openSupporter: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack {
                VStack {
                    Image(systemName: "fireplace.fill")
                        .font(.largeTitle)
                    Text("Campaign Hearth", bundle: .module)
                        .font(.largeTitle)
                        .bold()
                    Text(
                        "Gather your party and continue the story.",
                        bundle: .module
                    )
                    .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

                SupporterWelcomeCard(openSupporter: openSupporter)

                GameSetupSectionCard(
                    LocalizedStringResource("Choose your seat", bundle: .module),
                    systemImage: "person.3.fill"
                ) {
                    GameSetupRolePicker(selection: $role)
                    Text(role.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GameSetupSectionCard(
                    LocalizedStringResource("Prepare the session", bundle: .module),
                    systemImage: role.systemImage
                ) {
                    GameSetupRoleContent(root: root, selection: role)
                }

                ViewThatFits(in: .horizontal) {
                    HStack {
                        GameSetupStatisticsCard(
                            sessionCount: root.statisticsModel.summary.sessionCount,
                            openStatistics: openStatistics
                        )
                        GameSetupTipCard()
                    }

                    VStack {
                        GameSetupStatisticsCard(
                            sessionCount: root.statisticsModel.summary.sessionCount,
                            openStatistics: openStatistics
                        )
                        GameSetupTipCard()
                    }
                }
            }
            .frame(maxWidth: 900)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background { GameSetupBackdrop() }
        .moduleTint(.game)
    }
}

#Preview("1 · Campaign Hearth", traits: .mockData) {
    @Previewable @State var role: GameSetupRole = .player

    ManagedNavigationStack {
        CampaignHearthStartGameView(
            root: .preview,
            role: $role,
            openStatistics: {},
            openSupporter: {}
        )
    }
    .environment(\.supporterTier, .gold)
}
