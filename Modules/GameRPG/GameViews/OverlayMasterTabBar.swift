// @copyright André Trettin

import CoreRPG
import SwiftUI
import AdventureRPG
import TableRPG
import AudioRPG
import PhotoRPG
import MapRPG
import CharacterRPG
import PdfRPG
import SpaceRPG
import WeatherRPG

struct OverlayMasterTabBar: View {
    let root: GameRoot
    let adventureId: UUID
    let openAction: ((NetworkModules) -> Void)?

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.wideMode) private var wideMode

    var body: some View {
        ZStack(alignment: .trailing) {
#if os(macOS)
            onlyGameView
#elseif os(visionOS)
            onlyGameView
#else
            tabGameView
            tabSecondGameView
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
    
    var onlyGameView: some View {
        root.adventureRoot.viewController.gameView(root: root.adventureRoot, focusedIds: [adventureId])
            .environment(\.gameModus, .master)
            .gameOverlayTabBarView(value: NetworkModules.game)
            .frame(maxWidth: gameScreenModel.sideBarWidth, maxHeight: .infinity, alignment: .trailing)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
            .offset(x: gameScreenModel.showMainTab == .none ? gameScreenModel.sideBarWidth : 0)
            .opacity(gameScreenModel.showMainTab == .none ? 0 : 1)
            .shadow(radius: 8)
            .animation(.bouncy, value: gameScreenModel.showMainTab)
    }

    @ViewBuilder
    var tabGameView: some View {
        @Bindable var gameScreenModel = gameScreenModel
        NavigationStack {
            root.adventureRoot.viewController.gameView(root: root.adventureRoot, focusedIds: [adventureId])
                .environment(\.gameModus, .master)
        }
        .gameOverlayTabBarView(value: NetworkModules.game)
        .frame(maxWidth: gameScreenModel.sideBarWidth, maxHeight: .infinity, alignment: valueFor(iOS: .trailing, macOS: .trailing, tvOS: .trailing, visionOS: .leading))
#if !os(visionOS)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
#endif
        .offset(x: gameScreenModel.showMainTab == .none ? valueFor(iOS: gameScreenModel.sideBarWidth, macOS: gameScreenModel.sideBarWidth, tvOS: gameScreenModel.sideBarWidth, visionOS: -gameScreenModel.sideBarWidth) : 0)
        .opacity(gameScreenModel.showMainTab == .none ? 0 : 1)
        .shadow(radius: 8)
        .animation(.bouncy, value: gameScreenModel.showMainTab)
    }

    @ViewBuilder
    var tabSecondGameView: some View {
        @Bindable var gameScreenModel = gameScreenModel
        root.adventureRoot.viewController.gameModuleListView(root: root.adventureRoot, isPlayer: false)
            .environment(\.gameModus, .master)
            //.environment(\.showGame, true)
        .frame(maxWidth: gameScreenModel.sideBarWidth, maxHeight: .infinity, alignment: valueFor(iOS: .trailing, macOS: .trailing, tvOS: .trailing, visionOS: .leading))
#if !os(visionOS)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
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
                case .game, .map, .table, .audio, .photo:
                    gameScreenModel.resetToMainTab(toggle: false)
                    gameScreenModel.showGameType = $0
                case .dice:
                    // do nothing
                    break
                default:
                    gameScreenModel.resetToSettingsTab(toggle: false)
                    gameScreenModel.showSettingsType = $0
            }
        }
    }
}

#Preview {
    OverlayMasterTabBar(root: GameRoot.preview, adventureId: UUID(), openAction: nil)
        .environment(GameScreenModel())
}
