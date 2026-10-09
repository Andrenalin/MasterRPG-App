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

/// The module list inside the side panel. Only the game master's list pushes module views,
/// but the player's list uses the same navigation stack so both get identical insets from
/// it. See CODE_AUDIT_20 §8.10. The list itself shows no navigation bar;
/// `gameSidePanelContent()` supplies the top margin instead.
private struct GameModuleListPanel: View {
    let root: GameRoot
    let isPlayer: Bool

    var body: some View {
        NavigationStack {
            root.adventureRoot.viewController.gameModuleListView(root: root.adventureRoot, isPlayer: isPlayer)
                .navigationVisibility(false)
                .gameSidePanelContent()
        }
        .gameSidePanelIgnoringTrailingSafeArea()
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
