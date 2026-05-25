// @copyright André Trettin

import AdventureRPG
import CharacterRPG
import CoreRPG
import SwiftUI

struct OverlayPlayerTabBar: View {
    let root: GameRoot

    var body: some View {
        ZStack(alignment: .trailing) {
#if os(macOS) || os(visionOS)
            OnlyPlayerGameView(root: root)
#else
            TabPlayerGameView(root: root)
            TabPlayerSecondGameView(root: root)
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

private struct OnlyPlayerGameView: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        if root.gameModel.gameConfig.type != .observer {
            root.characterRoot.viewController.gameView(root: root.characterRoot, select: root.gameModel.selectedCharacter)
                .gameOverlayTabBarView(value: NetworkModules.game)
                .frame(maxWidth: gameScreenModel.sideBarWidth, maxHeight: .infinity, alignment: .trailing)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
                .offset(x: gameScreenModel.showMainTab == .none ? gameScreenModel.sideBarWidth : 0)
                .opacity(gameScreenModel.showMainTab == .none ? 0 : 1)
                .shadow(radius: 8)
                .animation(.bouncy, value: gameScreenModel.showMainTab)
        }
    }
}

private struct TabPlayerGameView: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        if root.gameModel.gameConfig.type != .observer {
            NavigationStack {
                if let characterId = root.gameModel.selectedCharacter {
                    root.characterRoot.viewController.gameView(root: root.characterRoot, select: characterId)
                }
            }
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
}

private struct TabPlayerSecondGameView: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        root.adventureRoot.viewController.gameModuleListView(root: root.adventureRoot, isPlayer: true)
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
    OverlayPlayerTabBar(root: GameRoot.preview)
        .environment(GameScreenModel())
}
