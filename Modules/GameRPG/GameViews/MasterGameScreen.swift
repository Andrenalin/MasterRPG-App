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
    @Environment(ScenesManager.self) private var scenesManager

    @State private var gameScreenModel = GameScreenModel()
    @State private var diceShowOptionModel = DiceDisplayModel()

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        ZStack {
            GameRootViewer(root: root, playerController: playerController, emptyTitle: "Select Map, Photo, Table, Weather or 3D Object", contentType: .master)
        }
        .overlay(alignment: .topLeading) {
            MasterOverlayMenu(root: root, adventureId: adventureId, playerController: playerController)
                .environment(diceShowOptionModel)
                .environment(gameScreenModel)
        }
        .focusSectionAll()
        .sheet(isPresented: $gameScreenModel.showExport) {
            if gameScreenModel.showExport {
                ExportProgressPanelView(exportController: root.adventureRoot.exportControllable, isSaveGame: true) {
                    root.saveGame()
                } finishedAction: {
                    gameScreenModel.showExport = false
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
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text("Do you really want to quit the game?", bundle: .module)
        }
        .task {
            await prepareWindows()
        }
        .onChange(of: gameScreenModel.showExport, initial: false) { old, new in
            if old == true && new == false {
                endGame()
            }
        }
#if os(macOS)
        .overlay(alignment: .trailing) {
            VStack {
                MasterMenuView()
            }
            .padding(12)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        }
#endif
#if os(visionOS)
        .gameImmersiveSpaceSync(root: root)
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
                MasterMenuView()
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
    func prepareWindows() async {
        do {
            try await Task.sleep(for: .seconds(0.6))
        } catch {
            return
        }

#if os(macOS) || os(visionOS)
        let savedMode = GameMainTabDisplayMode(rawValue: appSettingsModel.masterMainTabDisplayMode) ?? .hidden
        gameScreenModel.gameMainTabDisplayMode = savedMode

        switch savedMode {
        case .hidden:
            withAnimation { gameScreenModel.showMainTab = .none }

        case .inline:
            withAnimation { gameScreenModel.showMainTab = .game }

        case .window:
            if let adventureId = root.gameModel.selectedAdventure {
                scenesManager.openWindow(SceneId.viewerId(for: .adventure), selection: WindowItemSelection(itemId: adventureId))
            }
        }
#else
        let isShown = appSettingsModel.autoShowMasterMainTab
        gameScreenModel.showMainTabIOS = isShown

        if isShown {
            withAnimation { gameScreenModel.showMainTab = .game }
        } else {
            withAnimation { gameScreenModel.showMainTab = .none }
        }
#endif

#if os(visionOS)
        if appSettingsModel.showGameTableVolume {
            scenesManager.openWindow(SceneId.gameTable)
        }
#endif
    }

    func endGame() {
        appGameStateModel.isGameRunning = false
        Task {
            await root.stopGame()
        }
    }
}

#if os(visionOS) || os(macOS)
private struct MasterMenuView: View {
    @Environment(ScenesManager.self) private var scenesManager
    @State private var infoState: NetworkModules = .none

    var body: some View {
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
            if scenesManager.getSceneState(for: SceneId.sceneId(for: infoState)) == .closed {
                scenesManager.openWindow(SceneId.sceneId(for: infoState))
            } else {
                scenesManager.dismissWindow(SceneId.sceneId(for: infoState))
            }
            infoState = .none
        }
    }
}
#endif

private struct MasterOverlayMenu: View {
    let root: GameRoot
    let adventureId: UUID
    let playerController: PlayerController

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        OverlayGameLayout(root: root, hideDice: false) {
#if os(visionOS)
            EmptyView()
#else
            OverlayGameMenu(root: root, playerController: nil, isMaster: true)
#endif
        } sideOverlay: {
            OverlayMasterTabBar(root: root, adventureId: adventureId)
        } toolBarOverlay: {
            OverlayToolBar(root: root, playerController: playerController, isMaster: true)
        }
        .padding([.top, .leading], valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
        .id("masterOverlayLayout")
    }
}

#Preview("iPad") {
    MasterGameScreen(root: .preview, playerController: .preview, adventureId: UUID())
}
