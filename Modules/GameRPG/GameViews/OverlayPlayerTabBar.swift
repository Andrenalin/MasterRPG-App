// @copyright André Trettin

import CoreRPG
import SwiftUI
import CharacterRPG
import TableRPG
import PdfRPG
import AudioRPG
import PhotoRPG
import SpaceRPG
import DiceRPG
import AdventureRPG

struct OverlayPlayerTabBar: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.wideMode) private var wideMode
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel

    var body: some View {
        ZStack(alignment: .trailing) {
#if os(macOS)
            onlyGameView
#elseif os(visionOS)
            onlyGameView
#else
            if root.gameModel.gameConfig.type != .observer {
                tabGameView
            }
            tabSecondGameView
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .focusedSceneValue(\.selectedGameModule, tabSelectedModule)
    }

    @ViewBuilder
    var onlyGameView: some View {
        if root.gameModel.gameConfig.type != .observer {
            root.characterRoot.viewController.gameView(root: root.characterRoot, select: root.gameModel.selectedCharacter)
                .environment(\.gameModus, .player)
                .environment(\.showGame, true)
                .gameOverlayTabBarView(value: NetworkModules.game)
                .frame(maxWidth: gameScreenModel.sideBarWidth, maxHeight: .infinity, alignment: .trailing)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
                .cornerRadius(14)
                .offset(x: gameScreenModel.showMainTab == .none ? gameScreenModel.sideBarWidth : 0)
                .opacity(gameScreenModel.showMainTab == .none ? 0 : 1)
                .shadow(radius: 8)
                .animation(.bouncy, value: gameScreenModel.showMainTab)
        }
    }

    @ViewBuilder
    var tabGameView: some View {
        @Bindable var gameScreenModel = gameScreenModel
        NavigationStack {
            if root.gameModel.gameConfig.type != .observer, let characterId = root.gameModel.selectedCharacter {
                root.characterRoot.viewController.gameView(root: root.characterRoot, select: characterId)
                    .environment(\.gameModus, .player)
                    .environment(\.showGame, true)
            }
        }
        .frame(maxWidth: gameScreenModel.sideBarWidth, maxHeight: .infinity, alignment: valueFor(iOS: .trailing, macOS: .trailing, tvOS: .trailing, visionOS: .leading))
#if !os(visionOS)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .cornerRadius(14)
#endif
        .offset(x: gameScreenModel.showMainTab == .none ? valueFor(iOS: gameScreenModel.sideBarWidth, macOS: gameScreenModel.sideBarWidth, tvOS: gameScreenModel.sideBarWidth, visionOS: -gameScreenModel.sideBarWidth) : 0)
        .opacity(gameScreenModel.showMainTab == .none ? 0 : 1)
        .shadow(radius: 8)
        .animation(.bouncy, value: gameScreenModel.showMainTab)
    }

    @ViewBuilder
    var tabSecondGameView: some View {
        @Bindable var gameScreenModel = gameScreenModel
        root.adventureRoot.viewController.gameModuleListView(root: root.adventureRoot, isPlayer: true)
            .environment(\.gameModus, .player)
            .environment(\.showGame, true)
        .frame(maxWidth: gameScreenModel.sideBarWidth, maxHeight: .infinity, alignment: valueFor(iOS: .trailing, macOS: .trailing, tvOS: .trailing, visionOS: .leading))
#if !os(visionOS)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .cornerRadius(14)
#endif
        .offset(x: gameScreenModel.showSettingTab == .none ? valueFor(iOS: gameScreenModel.sideBarWidth, macOS: gameScreenModel.sideBarWidth, tvOS: gameScreenModel.sideBarWidth, visionOS: -gameScreenModel.sideBarWidth) : 0)
        .opacity(gameScreenModel.showSettingTab == .none ? 0 : 1)
        .shadow(radius: 8)
        .animation(.bouncy, value: gameScreenModel.showSettingTab)
    }

    var tabSelectedModule: Binding<NetworkModules> {
        Binding {
            gameScreenModel.showMainTab != .none ? gameScreenModel.showGameType : gameScreenModel.showSettingsType
        } set: {
            switch $0 {
                case .value, .table, .pdf, .audio, .photo:
                    gameScreenModel.resetToMainTab(toggle: false)
                    gameScreenModel.showGameType = $0
                default:
                    gameScreenModel.resetToSettingsTab(toggle: false)
                    gameScreenModel.showSettingsType = $0
            }
        }
    }
}

#Preview {
    OverlayPlayerTabBar(root: GameRoot.preview)
        .environment(GameScreenModel())
}
