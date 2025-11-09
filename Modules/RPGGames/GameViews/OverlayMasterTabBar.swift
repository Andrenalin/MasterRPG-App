// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGAdventures
import RPGTables
import RPGAudios
import RPGPhotos
import RPGMaps
import RPGValues
import RPGPdfs
import RPGSpaces
import RPGWeathers

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
        .focusedSceneValue(\.selectedGameModule, tabSelectedModule)
    }
    
    var onlyGameView: some View {
        root.adventureRoot.viewController.gameView(focusedIds: [adventureId], openAction: openAction)
            .environment(\.gameModus, .master)
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

    @ViewBuilder
    var tabGameView: some View {
        @Bindable var gameScreenModel = gameScreenModel
        TabView(selection: $gameScreenModel.showGameType) {
            Group {
                root.adventureRoot.viewController.gameView(focusedIds: [adventureId])
                    .gameOverlayTabBarView(value: NetworkModules.game)
                root.tableRoot.viewController.gameView()
                    .gameOverlayTabBarView(value: NetworkModules.table)
                root.audioRoot.viewController.gameView(root: root.audioRoot)
                    .gameOverlayTabBarView(value: NetworkModules.audio)
                root.photoRoot.viewController.gameView()
                    .gameOverlayTabBarView(value: NetworkModules.photo)
                root.mapRoot.viewController.gameView()
                    .gameOverlayTabBarView(value: NetworkModules.map)
            }
            .environment(\.gameModus, .master)
            .environment(\.showGame, true)
        }
#if os(iOS)
        .environment(\.horizontalSizeClass, .compact)
#endif
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
        TabView(selection: $gameScreenModel.showSettingsType) {
            Group {
                root.valueRoot.viewController.gameView()
                    .gameOverlayTabBarView(value: NetworkModules.value)
                root.pdfRoot.viewController.gameView()
                    .gameOverlayTabBarView(value: NetworkModules.pdf)
                root.spaceRoot.viewController.gameView(root: root.spaceRoot)
                    .gameOverlayTabBarView(value: NetworkModules.space)
                root.weatherRoot.viewController.gameView()
                    .gameOverlayTabBarView(value: NetworkModules.weather)
                root.viewController.logWindow()
                    .gameOverlayTabBarView(value: NetworkModules.setting)
            }
            .environment(\.gameModus, .master)
            .environment(\.showGame, true)
        }
#if os(iOS)
        .environment(\.horizontalSizeClass, .compact)
#endif
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
