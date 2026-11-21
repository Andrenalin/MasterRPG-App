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
#if os(visionOS)
    @Environment(\.pushWindow) private var pushWindow
#endif
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var gameScreenModel = GameScreenModel()
#if os(visionOS)
    /// One shot per game: a table the user closes stays closed.
    @State private var didOpenTable = false
#endif
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
                } onResult: { result in
                    // "Save and Quit" quits once the game is saved. A cancelled or failed save
                    // keeps the game running, so a wrong destination does not cost the game.
                    // See CODE_AUDIT_26 §5.21.
                    if result.endsSaveAndQuit {
                        endGame()
                    }
                }
            }
        }
        .alert(Text("Save Game?", bundle: .module), isPresented: $gameScreenModel.showQuitGameAlert) {
            Button {
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    gameScreenModel.showExport = true
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
            // Covers dismissal via system window chrome (visionOS's own close affordance, or
            // any other path that tears down this view without going through the in-app Quit
            // alert): the game/network session must not stay dangling with no way to end it.
            // No-ops harmlessly if a stop is already in flight or the game already stopped —
            // `stopGame()` coalesces concurrent callers (see GameRoot.stopGameTask).
            guard root.gameModel.gameConfig.state != .stopped else { return }
            endGame()
        }
        .persistGameDiceVisibility(
            gameScreenModel: gameScreenModel,
            diceDisplayModel: diceShowOptionModel
        )
#if os(visionOS)
        .gameScreenOrnaments(
            root: root,
            gameScreenModel: gameScreenModel,
            diceShowOptionModel: diceShowOptionModel,
            playerController: nil,
            isMaster: true
        ) {
            MasterSideMenu(root: root, adventureId: adventureId)
        }
#endif
    }
}

private extension MasterGameScreen {
    func prepareWindows() async {
#if os(visionOS)
        await openTableAtGameStart()
#endif
        do {
            try await Task.sleep(for: GameWindowToggle.windowPrepDelay)
        } catch {
            return
        }
        // The game may have been quit during the delay: its windows must not open then.
        guard appGameStateModel.isGameRunning, !root.isStopping, root.gameModel.gameConfig.state != .stopped else { return }

#if os(visionOS)
        // The adventure game view never appears inline on visionOS; it always
        // opens in its own external window, and nothing is persisted to
        // UserDefaults. The 3D table has been requested first (`openTableAtGameStart`), so this
        // window opens next to it.
        scenesManager.openWindow(
            SceneId.viewerId(for: .adventure),
            selection: WindowItemSelection(itemId: adventureId)
        )
#elseif os(macOS)
        if gameScreenModel.restoreMainTab(
            savedMode: appSettingsModel.masterMainTabDisplayMode,
            tab: .game,
            animation: accessibilityReduceMotion ? nil : .default
        ) {
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
#if os(visionOS)
            await GameWindowToggle.closeSecondaryWindows(scenesManager: scenesManager)
#endif
            await root.stopGame()
        }
    }
}

#if os(visionOS)
private extension MasterGameScreen {
    /// A game starts at the 3D table: the table opens at once and the 2D game screen, which has
    /// to stay alive behind it, is pushed aside. See `GameTableLauncher`.
    func openTableAtGameStart() async {
        // The screen can appear a moment before the game state turns to started.
        for _ in 0..<20 where !(appGameStateModel.isGameRunning && root.gameModel.gameConfig.state == .started) {
            guard (try? await Task.sleep(for: .milliseconds(50))) != nil else { return }
        }
        guard GameTableAutoOpenPolicy.shouldOpen(
            isGameRunning: appGameStateModel.isGameRunning,
            isStopping: root.isStopping,
            gameState: root.gameModel.gameConfig.state,
            tableSceneState: scenesManager.getSceneState(for: SceneId.gameTable),
            alreadyOpened: didOpenTable
        ) else { return }
        didOpenTable = true
        await GameTableLauncher.open(
            scenesManager: scenesManager,
            appSettingsModel: appSettingsModel,
            pushWindow: pushWindow
        )
    }
}
#endif

#Preview("iPad", traits: .mockData) {
    let root = GameRoot.previewFixture()
    MasterGameScreen(
        root: root,
        playerController: PlayerController(root: root, asGameMaster: true),
        adventureId: GamePreviewData.adventureID
    )
    .setAppSizeMode()
    .environment(AppFocusModel())
}
