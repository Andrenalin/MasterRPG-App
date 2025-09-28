// @copyright André Trettin

import AdventureRPG
import CharacterRPG
import CoreRPG
import DiceRPG
import MapRPG
import SwiftUI

struct MasterGameScreen: View {
    let root: GameRootController
    let playerController: PlayerController
    let adventureId: UUID
    
    //@Environment(\.showGameActions) private var showGameActions

    @State private var gameScreenModel = GameScreenModel()
    @State private var infoState: NetworkModules = .none

#if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(WindowStateModel.self) private var windowStateModel
#endif
    @State private var diceShowOptionModel = DiceDisplayModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
//            GameRootViewer(root: root, playerController: playerController, emptyTitle: "Select Map, Photo, Table, Weather or 3D Object") { mapId in
//                //root.mapRoot.viewController.gameMasterMapView(id: mapId)
//            }
            
            overlayMenu
        }
        .environment(\.gameModus, .master)
        //.environment(\.mapActions, root.mapRoot.mapActions)
//        .environment(\.valueActions, root.valueRoot.valueActions)
        .overlay(alignment: .center) {
            if gameScreenModel.showExport {
//                ExportProgressFile(exportController: root.adventureRoot.gameControllable.rootExportControllable, showExport: $gameScreenModel.showExport) {
//                    root.saveGame()
//                }
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
            root.diceRoot.viewController.dicePlayerView()
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
            root.diceRoot.viewController.diceActionBarView()
                .padding(.top, 12)
                .environment(diceShowOptionModel)
        }
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            root.diceRoot.viewController.diceRollView()
                .padding(.top, 56)
                .environment(diceShowOptionModel)
        }
        .ornament(attachmentAnchor: .scene(.bottomTrailing), contentAlignment: .topTrailing) {
            root.diceRoot.viewController.diceResultView()
                .padding(.top, 12)
                .environment(diceShowOptionModel)
        }
#endif
    }
}

private extension MasterGameScreen {
    func prepareWindows() {
#if os(iOS) || os(visionOS)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.1))
            gameScreenModel.showGameType <=> .table
            withAnimation { gameScreenModel.showMainTab <=> .game }
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation { gameScreenModel.showGameType <=> .game }
        }
#elseif os(macOS)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.1))
            withAnimation { gameScreenModel.showMainTab <=> .game }
        }
#endif
#if os(visionOS)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            showWindow(for: .adventure)
            try? await Task.sleep(for: .seconds(0.15))
            showWindow(for: .map)
            try? await Task.sleep(for: .seconds(0.15))
            showWindow(for: .table)
            try? await Task.sleep(for: .seconds(0.15))
            showWindow(for: .pdf)
        }
#endif
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
        //showGameActions.show(false)
        Task {
            await root.stopGame()
        }
    }
    
    func showWindow(for module: NetworkModules) {
#if os(macOS) || os(visionOS)
        guard !windowStateModel.openWindowState[module, default: false] else { return }
        windowStateModel.openWindowState[module] = true
        openWindow(id: module.linkWindowId)
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

            if windowStateModel.openWindowState[infoState, default: false] {
                windowStateModel.openWindowState[infoState] = false
                dismissWindow(id: infoState.linkWindowId)
            } else {
                windowStateModel.openWindowState[infoState] = true
                openWindow(id: infoState.linkWindowId)
            }
            infoState = .none
        }
    }
#endif
}

//#Preview("iPad") {
//    MasterGameScreen(root: .preview, playerController: .preview, adventureId: UUID())
//        .environment(\.wideMode, .small)
//    //.frame(width: 800)
//}

//#Preview("iPhone") {
//    MasterGameScreen(root: .preview, playerController: .preview, adventureId: UUID())
//        .environment(\.wideMode, .small)
//    //.frame(width: 800)
//}
