// @copyright André Trettin

import AdventureRPG
import CoreRPG
import Foundation
import SwiftUI

struct TabGameView: View {
    let root: GameRoot
    let adventureId: UUID

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        NavigationStack {
            root.adventureRoot.viewController.gameView(
                root: root.adventureRoot,
                focusedIds: [adventureId]
            )
            .gameSidePanelContent()
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

#Preview {
    TabGameView(root: .previewFixture(), adventureId: GamePreviewData.adventureId)
        .environment(GameScreenModel())
}
