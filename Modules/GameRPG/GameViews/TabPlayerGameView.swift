// @copyright André Trettin

import CharacterRPG
import CoreRPG
import SwiftUI

struct TabPlayerGameView: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        if root.gameModel.gameType != .observer {
            NavigationStack {
                if let characterId = root.gameModel.selectedCharacter {
                    root.characterRoot.viewController.gameView(
                        root: root.characterRoot,
                        select: characterId
                    )
                    .gameSidePanelContent()
                }
            }
            .gameSidePanelIgnoringTrailingSafeArea()
            .gameSidePanel(
                isShown: gameScreenModel.showMainTab != .none,
                width: gameScreenModel.sideBarWidth,
                animationValue: gameScreenModel.showMainTab,
                onWidthChange: gameScreenModel.updateInlineMainOverlayWidth
            )
        }
    }
}

#Preview {
    TabPlayerGameView(root: .previewFixture(game: .player))
        .environment(GameScreenModel())
}
