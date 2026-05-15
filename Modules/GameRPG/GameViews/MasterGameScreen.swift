// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI
import MapRPG
import CharacterRPG
import AdventureRPG

struct MasterGameScreen: View {
    let root: GameRoot
    let playerController: PlayerController
    let adventureId: UUID
    
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(AppSettingsModel.self) private var appSettingsModel
    
    @State private var gameScreenModel = GameScreenModel()
    @State private var infoState: NetworkModules = .none
    
    @Environment(ScenesManager.self) private var sceneManager
    
    @State private var diceShowOptionModel = DiceDisplayModel()
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            GameRootViewer(root: root, playerController: playerController, emptyTitle: "Select Map, Photo, Table, Weather or 3D Object") { mapId in
                root.mapRoot.viewController.gameMasterMapView(root: root.mapRoot, id: mapId)
            }
            
            overlayMenu
        }
        .environment(\.mapActions, root.mapRoot.mapActions)
        .environment(\.valueActions, root.characterRoot.valueActions)
        .overlay(alignment: .center) {
            if gameScreenModel.showExport {
                ExportProgressFile(exportController: root.adventureRoot.exportControllable, showExport: $gameScreenModel.showExport) {
                    root.saveGame()
                }
            }
        }
        .alert(Text("Save Game?", bundle: .module), isPresented: $gameScreenModel.showQuitGameAlert) {
            Button {
                withAnimation { gameScreenModel.showExport.toggle() }
            } label: {
                Text("Save and Quit", bundle: .module)
            }
            Button {
                endGame()
            } label: {
                Text("Quit", bundle: .module)
            }
            Button {
            } label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text("Do you really want to quit the game?", bundle: .module)
        }
        .onAppear {
            prepareWindows()
        }
        .onChange(of: gameScreenModel.showExport, initial: false) { old, new in
            if old == true && new == false {
                endGame()
            }
        }
#if os(visionOS)
        .ornament(attachmentAnchor: .scene(.topLeading), contentAlignment: .topTrailing) {
            root.diceRoot.viewController.dicePlayerView(root: root.diceRoot)
                .environment(diceShowOptionModel)
        }
        .ornament(attachmentAnchor: .scene(.topTrailing), contentAlignment: .bottomTrailing) {
            OverlayGameMenu(root: root, playerController: nil, isMaster: true)
                .environment(diceShowOptionModel)
                .environment(gameScreenModel)
                .padding(.bottom, 12)
            
        }
        .ornament(attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
            VStack {
                menuView
            }
            .padding(12)
        }
        .ornament(attachmentAnchor: .scene(.bottomLeading), contentAlignment: .topLeading) {
            root.diceRoot.viewController.diceActionBarView(root: root.diceRoot)
                .padding(.top, 12)
                .environment(diceShowOptionModel)
        }
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            root.diceRoot.viewController.diceRollView(root: root.diceRoot)
                .padding(.top, 56)
                .environment(diceShowOptionModel)
        }
        .ornament(attachmentAnchor: .scene(.bottomTrailing), contentAlignment: .topTrailing) {
            root.diceRoot.viewController.diceResultView(root: root.diceRoot)
                .padding(.top, 12)
                .environment(diceShowOptionModel)
        }
#endif
    }
}

private extension MasterGameScreen {
    func prepareWindows() {
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            
#if os(macOS) || os(visionOS)
            // Restore three-state display mode from UserDefaults
            let savedMode = GameMainTabDisplayMode(rawValue: appSettingsModel.masterMainTabDisplayMode) ?? .hidden
            gameScreenModel.gameMainTabDisplayMode = savedMode
            
            // Apply the saved mode
            switch savedMode {
            case .hidden:
                withAnimation { gameScreenModel.showMainTab = .none }
                
            case .inline:
                withAnimation { gameScreenModel.showMainTab = .game }
                
            case .window:
                // Open the adventure viewer window
                if let adventureId = root.gameModel.selectedAdventure {
                    sceneManager.openWindow(SceneId.viewerId(for: .adventure), selection: WindowItemSelection(itemId: adventureId))
                }
            }
            
#else
            // iOS/tvOS: Simple show/hide toggle
            let isShown = appSettingsModel.autoShowMasterMainTab
            gameScreenModel.showMainTabIOS = isShown
            
            if isShown {
                withAnimation { gameScreenModel.showMainTab = .game }
            } else {
                withAnimation { gameScreenModel.showMainTab = .none }
            }
#endif
            
#if os(visionOS)
            // Restore table volume state
            if appSettingsModel.showGameTableVolume {
                sceneManager.openWindow(SceneId.gameTable)
            }
#endif
            
            
        }
    }
    
    var overlayMenu: some View {
        OverlayGameLayout(root: root, hideDice: false) {
#if os(visionOS)
            EmptyView()
#else
            OverlayGameMenu(root: root, playerController: nil, isMaster: true)
#endif
        } sideOverlay: {
            OverlayMasterTabBar(root: root, adventureId: adventureId, openAction: showWindow(for:))
        } toolBarOverlay: {
            OverlayToolBar(root: root, playerController: playerController, isMaster: true)
        }
        .padding([.top, .leading], valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
        .environment(diceShowOptionModel)
        .environment(gameScreenModel)
    }
    
    func endGame() {
        appGameStateModel.isGameRunning = false
        Task {
            await root.stopGame()
        }
    }
    
    func showWindow(for module: NetworkModules) {
#if os(macOS) || os(visionOS)
        guard sceneManager.getSceneState(for: SceneId.sceneId(for: module)) == .closed else { return }
        sceneManager.openWindow(SceneId.sceneId(for: module))
#endif
    }
    
#if os(visionOS)
    var menuView: some View {
        Group {
            GameToolBarButtonView(valueType: .adventure, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .audio, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .dice, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .map, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .pdf, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .photo, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .space, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .table, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .value, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .weather, alwaysSet: true, showType: $infoState)
        }
        .onChange(of: infoState) {
            guard infoState != .none else { return }
            
            if sceneManager.getSceneState(for: SceneId.sceneId(for: infoState)) == .closed {
                sceneManager.openWindow(SceneId.sceneId(for: infoState))
            } else {
                sceneManager.dismissWindow(SceneId.sceneId(for: infoState))
            }
            infoState = .none
        }
    }
#endif
}

#Preview("iPad") {
    MasterGameScreen(root: .preview, playerController: .preview, adventureId: UUID())
    //.frame(width: 800)
}

//#Preview("iPhone") {
//    MasterGameScreen(root: .preview, playerController: .preview, adventureId: UUID())
//    //.frame(width: 800)
//}
