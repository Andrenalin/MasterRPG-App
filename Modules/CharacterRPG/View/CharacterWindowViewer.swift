// @copyright André Trettin

import CoreRPG
import SwiftUI

/// The character viewer of its own window (Mac, visionOS, iPad).
///
/// While a game runs and the window shows the character the game focuses on, it is the game view in a
/// window: it uses the game configuration, so it gets the game's sheet model and the add-entry
/// control the 2D game screen has. Any other character window stays the plain reader.
struct CharacterWindowViewer: View {
    let root: CharacterRootModel
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
