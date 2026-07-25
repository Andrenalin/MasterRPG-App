// @copyright André Trettin

import CoreRPG
import SwiftUI

/// A clear three-step checklist for first-time and occasional players.
struct QuestBoardStartGameView: View {
    let root: GameRoot
    @Binding var role: GameSetupRole
    let openStatistics: @MainActor () -> Void
    let openSupporter: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Quest Board", bundle: .module)
                    .font(.largeTitle)
                    .bold()
                Text(
                    "Complete the three preparations, then begin.",
                    bundle: .module
                )
                .foregroundStyle(.secondary)

                SupporterWelcomeCard(openSupporter: openSupporter)

                QuestBoardStep(number: 1, title: "Choose your role", isComplete: true) {
                    GameSetupRolePicker(selection: $role)
                }

                QuestBoardStep(
                    number: 2,
                    title: role == .join ? "Find a game" : "Choose your game item",
                    isComplete: selectionIsComplete
                ) {
                    GameSetupRoleContent(root: root, selection: role)
                }

                QuestBoardStep(
                    number: 3,
                    title: "Start the adventure",
                    isComplete: root.gameModel.gameConfig.state == .started
                ) {
                    Text(
                        "The action above starts or joins the session when your selection is ready.",
                        bundle: .module
                    )
                    .foregroundStyle(.secondary)
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
            .frame(maxWidth: 820)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background { GameSetupBackdrop() }
        .moduleTint(.game)
    }

    private var selectionIsComplete: Bool {
        switch role {
#if !os(tvOS)
        case .player:
            root.gameModel.selectedCharacter != nil
        case .master:
            root.gameModel.selectedAdventure != nil
#endif
        case .join:
            false
        }
    }

}

private struct QuestBoardStep<Content: View>: View {
    let number: Int
    let title: LocalizedStringKey
    let isComplete: Bool
    @ViewBuilder let content: Content

    @Environment(\.appTheme) private var theme

    init(
        number: Int,
        title: LocalizedStringKey,
        isComplete: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.number = number
        self.title = title
        self.isComplete = isComplete
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "\(number).circle.fill")
                .font(.title)
                .foregroundStyle(
                    isComplete ? theme.tint(for: .adventure) : theme.secondaryForegroundColor
                )

            VStack(alignment: .leading) {
                Text(title, bundle: .module)
                    .font(.headline)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            theme.panelColor.opacity(0.86),
            in: .rect(cornerRadius: 20)
        )
    }
}

#Preview("3 · Quest Board", traits: .mockData) {
    @Previewable @State var role: GameSetupRole = .player

    ManagedNavigationStack {
        QuestBoardStartGameView(
            root: .preview,
            role: $role,
            openStatistics: {},
            openSupporter: {}
        )
    }
}
