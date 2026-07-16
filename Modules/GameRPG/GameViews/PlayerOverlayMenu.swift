// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PlayerOverlayMenu: View {
    let root: GameRoot
    let playerController: PlayerController

    var body: some View {
        OverlayGameLayout(root: root, hideDice: root.gameModel.gameType == .observer) {
#if os(visionOS) || os(macOS)
            EmptyView()
#else
            OverlayGameMenu(root: root, playerController: playerController, isMaster: false)
#endif
        } sideOverlay: {
            OverlayPlayerTabBar(root: root)
        } toolBarOverlay: {
            OverlayToolBar(root: root, playerController: playerController, isMaster: false)
        }
#if os(macOS)
        .toolbar {
            GameToolbarContent(root: root, role: .player, playerController: playerController)
        }
#endif
        .padding(.leading, valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
        .id("playerOverlayLayout")
    }
}

#Preview(traits: .mockData) {
    let root = GameRoot.previewFixture(game: .player)
    PlayerOverlayMenu(
        root: root,
        playerController: PlayerController(root: root, asGameMaster: false)
    )
    .environment(GameScreenModel())
}
