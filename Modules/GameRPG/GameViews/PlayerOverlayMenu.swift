// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PlayerOverlayMenu: View {
    let root: GameRoot
    let playerController: PlayerController

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        OverlayGameLayout(
            root: root,
            hideDice: root.gameModel.gameType == .observer,
            offersQuickDice: root.offersQuickDice(isMaster: false)
        ) {
#if os(visionOS) || os(macOS)
            EmptyView()
#else
            OverlayGameMenu(root: root, playerController: playerController, isMaster: false)
#endif
        } sideOverlay: {
            OverlayPlayerTabBar(root: root)
        } moduleMenuOverlay: {
#if os(macOS)
            if gameScreenModel.isSideMenuVisible {
                PlayerSideMenu(root: root)
                    .offset(x: gameScreenModel.isInlineSidebarVisible ? -gameScreenModel.inlineMainOverlayWidth : 0)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .animation(reduceMotion ? nil : .default, value: gameScreenModel.inlineMainOverlayWidth)
            }
#else
            EmptyView()
#endif
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
