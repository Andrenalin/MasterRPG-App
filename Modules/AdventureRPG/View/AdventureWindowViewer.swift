// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The adventure viewer of its own window (Mac, visionOS, iPad).
///
/// While a game runs and the window shows the adventure the game focuses on, it is the game view in a
/// window: it uses the game configuration, so it gets the game's sheet model and the Ask AI
/// control the 2D game screen has. Any other adventure window stays the plain reader.
struct AdventureWindowViewer: View {
    let root: AdventureRootModel
    let itemId: UUID
    let closeButton: Bool

    @Environment(AppGameStateModel.self) private var appGameStateModel

    var body: some View {
        root.viewController.viewer(
            root: root,
            itemId: itemId,
            configuration: ViewerConfiguration(
                closeButton: closeButton,
                addToolbar: true,
                isGame: isGameItem,
                isWindow: true
            )
        )
    }

    private var isGameItem: Bool {
        appGameStateModel.isGameRunning && root.gameController.gameModel.focusItemIds.contains(itemId)
    }
}
