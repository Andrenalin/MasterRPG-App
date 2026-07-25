// @copyright André Trettin

import CoreRPG
import SwiftUI

/// An expressive, role-first gateway that minimizes secondary information.
struct PortalGateStartGameView: View {
    let root: GameRoot
    @Binding var role: GameSetupRole
    let openStatistics: @MainActor () -> Void
    let openSupporter: @MainActor () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack {
                ZStack {
                    Circle()
                        .stroke(theme.tint(for: .adventure).opacity(0.35), lineWidth: 12)
                    Circle()
                        .stroke(theme.tint(for: .dice), style: .init(lineWidth: 3, dash: [8, 8]))
                        .padding()
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(theme.tint(for: .adventure))
                }
                .frame(width: 150, height: 150)
                .accessibilityHidden(true)

                Text("Portal Gate", bundle: .module)
                    .font(.largeTitle)
                    .bold()
                Text("How will you enter tonight’s story?", bundle: .module)
                    .foregroundStyle(.secondary)

                GameSetupRoleCards(selection: $role)

                GameSetupSectionCard(
                    role.title,
                    systemImage: role.systemImage
                ) {
                    GameSetupRoleContent(root: root, selection: role)
                }

                SupporterWelcomeCard(openSupporter: openSupporter)

                HStack {
                    GameSetupStatisticsCard(
                        sessionCount: root.statisticsModel.summary.sessionCount,
                        openStatistics: openStatistics
                    )
                    GameSetupTipCard()
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

#Preview("4 · Portal Gate", traits: .mockData) {
    @Previewable @State var role: GameSetupRole = .master

    ManagedNavigationStack {
        PortalGateStartGameView(
            root: .preview,
            role: $role,
            openStatistics: {},
            openSupporter: {}
        )
    }
    .environment(\.supporterTier, .bronze)
}
