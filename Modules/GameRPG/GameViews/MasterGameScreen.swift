// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI
import MapRPG
import CharacterRPG
import AdventureRPG
import AudioRPG

struct MasterGameScreen: View {
    let root: GameRoot
    let playerController: PlayerController
    let adventureId: UUID

    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(AppSettingsModel.self) private var appSettingsModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var gameScreenModel = GameScreenModel()
    @State private var diceShowOptionModel = DiceDisplayModel()

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        GameScreenLayer {
            GameRootViewer(
                root: root,
                playerController: playerController,
                emptyTitle: "Select Map, Photo, Table, Weather or 3D Object",
                contentType: .master,
                gameScreenModel: gameScreenModel
            )
        } chrome: {
            MasterOverlayMenu(
                root: root,
                adventureId: adventureId,
                playerController: playerController
            )
            .environment(diceShowOptionModel)
            .environment(gameScreenModel)
            .environment(gameScreenModel.searchBarVisibleModel)
        }
        .overlay {
            BattleRoundGameChrome(root: root)
                .environment(gameScreenModel)
        }
        .focusSectionAll()
        .sheet(isPresented: $gameScreenModel.showExport) {
            if gameScreenModel.showExport {
                ExportProgressPanelView(
                    exportController: root.adventureRoot.exportControllable,
                    isSaveGame: true,
                    saveGameName: root.adventureRoot.networkTitle(for: adventureId)
                ) {
                    root.saveGame()
                } finishedAction: {
                    gameScreenModel.showExport = false
                }
            }
        }
        .alert(Text("Save Game?", bundle: .module), isPresented: $gameScreenModel.showQuitGameAlert) {
            Button {
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    gameScreenModel.showExport.toggle()
                }
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
        .onDisappear {
            root.mapRoot.rootModel.clearGameEditorSession()
        }
        .onChange(of: gameScreenModel.showExport, initial: false) { old, new in
            if old == true && new == false {
                endGame()
            }
        }
        .persistGameDiceVisibility(
            gameScreenModel: gameScreenModel,
            diceDisplayModel: diceShowOptionModel
        )
#if os(visionOS)
        .gameImmersiveSpaceSync(root: root)
        .ornament(attachmentAnchor: .scene(.topLeading), contentAlignment: .bottomLeading) {
            GameOrnamentCloseButton()
                .environment(gameScreenModel)
        }
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
                MasterSideMenu(adventureId: adventureId)
                    .environment(gameScreenModel)
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

#if os(visionOS)
        // The adventure game view never appears inline on visionOS; it always
        // opens in its own external window, and nothing is persisted to
        // UserDefaults. The 3D GameTable volume always starts closed
        // (GameTableWindowButton opens it on demand).
        scenesManager.openWindow(
            SceneId.viewerId(for: .adventure),
            selection: WindowItemSelection(itemId: adventureId)
        )
#elseif os(macOS)
        let savedMode = GameMainTabDisplayMode(rawValue: appSettingsModel.masterMainTabDisplayMode) ?? .hidden
        gameScreenModel.gameMainTabDisplayMode = savedMode

        switch savedMode {
        case .hidden:
            withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.showMainTab = .none }

        case .inline:
            withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.showMainTab = .game }

        case .window:
            withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.showMainTab = .none }
            scenesManager.openWindow(
                SceneId.viewerId(for: .adventure),
                selection: WindowItemSelection(itemId: adventureId)
            )
        }
#else
        let isShown = appSettingsModel.autoShowMasterMainTab
        gameScreenModel.showMainTabIOS = isShown

        if isShown {
            withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.showMainTab = .game }
        } else {
            withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.showMainTab = .none }
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

extension ScenesManager.SceneState {
    var isPresentedInGameMenu: Bool {
        switch self {
        case .opening, .opened:
            true
        case .closing, .closed:
            false
        }
    }
}

#Preview("iPad", traits: .mockData) {
    let root = GameRoot.previewFixture()
    MasterGameScreen(
        root: root,
        playerController: PlayerController(root: root, asGameMaster: true),
        adventureId: GamePreviewData.adventureID
    )
    .setAppSizeMode()
}
