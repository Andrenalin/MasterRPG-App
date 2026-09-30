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
        moduleList
            .gameSidePanel(
                isShown: gameScreenModel.showSettingTab != .none,
                width: gameScreenModel.sideBarWidth,
                animationValue: gameScreenModel.showSettingTab
            )
    }
}

private extension TabSecondGameView {
    /// The game master's list pushes module views, so it brings its own navigation stack.
    @ViewBuilder
    var moduleList: some View {
        if isPlayer {
            root.adventureRoot.viewController.gameModuleListView(root: root.adventureRoot, isPlayer: true)
        } else {
            NavigationStack {
                root.adventureRoot.viewController.gameModuleListView(root: root.adventureRoot, isPlayer: false)
                    .navigationVisibility(true)
            }
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
