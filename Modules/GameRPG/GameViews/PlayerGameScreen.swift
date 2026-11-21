// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI
import MapRPG
import SpaceRPG

struct PlayerGameScreen: View {
    let root: GameRoot
    let playerController: PlayerController

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
                emptyTitle: "Game is running",
                contentType: .player,
                gameScreenModel: gameScreenModel
            )
        } chrome: {
            PlayerOverlayMenu(root: root, playerController: playerController)
                .environment(diceShowOptionModel)
                .environment(gameScreenModel)
                .environment(gameScreenModel.searchBarVisibleModel)
        }
        .overlay {
            BattleRoundGameChrome(root: root)
                .environment(gameScreenModel)
        }
        .focusSectionAll()
        .alert(Text("Quit Game?", bundle: .module), isPresented: $gameScreenModel.showQuitGameAlert) {
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
        .onChange(of: root.gameModel.selectedCharacter, initial: true) { _, characterId in
            root.quickDiceSlots.load(characterId: characterId)
        }
        .onChange(of: root.offersQuickDice(isMaster: false), initial: true) { _, isOffered in
            root.quickDiceSlots.isOfferedNow = isOffered
        }
        .onDisappear {
            root.quickDiceSlots.load(characterId: nil)
            root.quickDiceSlots.isOfferedNow = false
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
            playerController: playerController,
            isMaster: false
        ) {
            PlayerSideMenu(root: root)
        }
#endif
    }
}

private extension PlayerGameScreen {
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
        // The character game view never appears inline on visionOS; it always
        // opens in its own external window, and nothing is persisted to
        // UserDefaults. The 3D table has been requested first (`openTableAtGameStart`), so this
        // window opens next to it.
        if let characterId = root.gameModel.selectedCharacter {
            scenesManager.openWindow(SceneId.viewerId(for: .value), selection: WindowItemSelection(itemId: characterId))
        }
#elseif os(macOS)
        if gameScreenModel.restoreMainTab(
            savedMode: appSettingsModel.playerMainTabDisplayMode,
            tab: .value,
            animation: accessibilityReduceMotion ? nil : .default
        ), let characterId = root.gameModel.selectedCharacter {
            scenesManager.openWindow(SceneId.viewerId(for: .value), selection: WindowItemSelection(itemId: characterId))
        }
#else
        let isShown = appSettingsModel.autoShowPlayerMainTab
        gameScreenModel.showMainTabIOS = isShown

        if isShown {
#if os(iOS)
            if root.gameModel.gameType == .observer {
                gameScreenModel.iOSSidebarShowsPrimaryView = false
                withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.showSettingTab = .setting }
            } else {
                withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.showMainTab = .value }
            }
#else
            withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.showMainTab = .value }
#endif
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
private extension PlayerGameScreen {
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

#Preview(traits: .mockData) {
    let root = GameRoot.previewFixture(game: .player)
    PlayerGameScreen(
        root: root,
        playerController: PlayerController(root: root, asGameMaster: false)
    )
    .setAppSizeMode()
}
