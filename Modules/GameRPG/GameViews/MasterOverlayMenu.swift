// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct MasterOverlayMenu: View {
    let root: GameRoot
    let adventureId: UUID
    let playerController: PlayerController

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        OverlayGameLayout(root: root, hideDice: false) {
#if os(visionOS) || os(macOS)
            EmptyView()
#else
            OverlayGameMenu(root: root, playerController: nil, isMaster: true)
#endif
        } sideOverlay: {
            OverlayMasterTabBar(root: root, adventureId: adventureId)
        } moduleMenuOverlay: {
#if os(macOS)
            if gameScreenModel.isSideMenuVisible {
                MasterSideMenu(adventureId: adventureId)
                    .offset(x: gameScreenModel.isInlineSidebarVisible ? -gameScreenModel.inlineMainOverlayWidth : 0)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .animation(.default, value: gameScreenModel.inlineMainOverlayWidth)
            }
#else
            EmptyView()
#endif
        } toolBarOverlay: {
            OverlayToolBar(root: root, playerController: playerController, isMaster: true)
        }
#if os(macOS)
        .toolbar {
            GameToolbarContent(root: root, role: .master, playerController: nil)
        }
#endif
        .padding(.leading, valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
        .id("masterOverlayLayout")
    }
}

#Preview(traits: .mockData) {
    let root = GameRoot.previewFixture()
    MasterOverlayMenu(
        root: root,
        adventureId: GamePreviewData.adventureID,
        playerController: PlayerController(root: root, asGameMaster: true)
    )
    .environment(GameScreenModel())
}
