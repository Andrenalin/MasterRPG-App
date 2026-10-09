// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

/// The game screen's slide-in module list, for the game master and players alike (it was two
/// copied files). See CODE_AUDIT_19 §9.19.
struct TabSecondGameView: View {
    let root: GameRoot
    var isPlayer = false

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        GameModuleListPanel(root: root, isPlayer: isPlayer)
            .gameSidePanel(
                isShown: gameScreenModel.showSettingTab != .none,
                width: gameScreenModel.sideBarWidth,
                animationValue: gameScreenModel.showSettingTab
            )
    }
}

/// The module list inside the side panel. The game master's list pushes module views, so it
/// brings its own navigation stack. See CODE_AUDIT_20 §8.10. The list itself shows no
/// navigation bar; `gameSidePanelContent(marginWithoutTopSafeArea:)` supplies the top margin the bar used to give.
private struct GameModuleListPanel: View {
    let root: GameRoot
    let isPlayer: Bool

    var body: some View {
        if isPlayer {
            root.adventureRoot.viewController.gameModuleListView(root: root.adventureRoot, isPlayer: true)
                .gameSidePanelContent(marginWithoutTopSafeArea: GameScreenModel.sidePanelDuoTopMargin)
        } else {
            NavigationStack {
                root.adventureRoot.viewController.gameModuleListView(root: root.adventureRoot, isPlayer: false)
                    .navigationVisibility(false)
                    .gameSidePanelContent(marginWithoutTopSafeArea: GameScreenModel.sidePanelDuoTopMargin)
            }
            .gameSidePanelIgnoringTrailingSafeArea()
        }
    }
}

#Preview {
    TabSecondGameView(root: .previewFixture())
        .environment(GameScreenModel())
}

#Preview("Player") {
    TabSecondGameView(root: .previewFixture(game: .player), isPlayer: true)
        .environment(GameScreenModel())
}
