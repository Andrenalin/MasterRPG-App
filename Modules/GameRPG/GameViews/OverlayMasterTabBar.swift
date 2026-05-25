// @copyright André Trettin

import AdventureRPG
import CoreRPG
import SwiftUI

struct OverlayMasterTabBar: View {
    let root: GameRoot
    let adventureId: UUID

    var body: some View {
        ZStack(alignment: .trailing) {
#if os(macOS) || os(visionOS)
            OnlyGameView(root: root, adventureId: adventureId)
#else
            TabGameView(root: root, adventureId: adventureId)
            TabSecondGameView(root: root)
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

private struct OnlyGameView: View {
    let root: GameRoot
    let adventureId: UUID

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        root.adventureRoot.viewController.gameView(root: root.adventureRoot, focusedIds: [adventureId])
            .gameOverlayTabBarView(value: NetworkModules.game)
            .frame(maxWidth: gameScreenModel.sideBarWidth, maxHeight: .infinity, alignment: .trailing)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
            .offset(x: gameScreenModel.showMainTab == .none ? gameScreenModel.sideBarWidth : 0)
            .opacity(gameScreenModel.showMainTab == .none ? 0 : 1)
            .shadow(radius: 8)
            .animation(.bouncy, value: gameScreenModel.showMainTab)
    }
}

private struct TabGameView: View {
    let root: GameRoot
    let adventureId: UUID

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        ManagedNavigationStack {
            root.adventureRoot.viewController.gameView(root: root.adventureRoot, focusedIds: [adventureId])
        }
        .gameOverlayTabBarView(value: NetworkModules.game)
        .frame(maxWidth: gameScreenModel.sideBarWidth, maxHeight: .infinity,
               alignment: valueFor(iOS: .trailing, macOS: .trailing, tvOS: .trailing, visionOS: .leading))
#if !os(visionOS)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
#endif
        .offset(x: gameScreenModel.showMainTab == .none
                ? valueFor(iOS: gameScreenModel.sideBarWidth, macOS: gameScreenModel.sideBarWidth, tvOS: gameScreenModel.sideBarWidth, visionOS: -gameScreenModel.sideBarWidth)
                : 0)
        .opacity(gameScreenModel.showMainTab == .none ? 0 : 1)
        .shadow(radius: 8)
        .animation(.bouncy, value: gameScreenModel.showMainTab)
    }
}

private struct TabSecondGameView: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        root.adventureRoot.viewController.gameModuleListView(root: root.adventureRoot, isPlayer: false)
            .frame(maxWidth: gameScreenModel.sideBarWidth, maxHeight: .infinity,
                   alignment: valueFor(iOS: .trailing, macOS: .trailing, tvOS: .trailing, visionOS: .leading))
#if !os(visionOS)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
#endif
        .offset(x: gameScreenModel.showSettingTab == .none
                ? valueFor(iOS: gameScreenModel.sideBarWidth, macOS: gameScreenModel.sideBarWidth, tvOS: gameScreenModel.sideBarWidth, visionOS: -gameScreenModel.sideBarWidth)
                : 0)
        .opacity(gameScreenModel.showSettingTab == .none ? 0 : 1)
        .shadow(radius: 8)
        .animation(.bouncy, value: gameScreenModel.showSettingTab)
    }
}

#Preview {
    OverlayMasterTabBar(root: GameRoot.preview, adventureId: UUID())
        .environment(GameScreenModel())
}
