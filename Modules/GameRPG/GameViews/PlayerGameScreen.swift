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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var gameScreenModel = GameScreenModel()
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
        .onDisappear {
            root.quickDiceSlots.load(characterId: nil)
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
        do {
            try await Task.sleep(for: GameWindowToggle.windowPrepDelay)
        } catch {
            return
        }

#if os(visionOS)
        // The character game view never appears inline on visionOS; it always
        // opens in its own external window, and nothing is persisted to
        // UserDefaults. The 3D GameTable volume always starts closed
        // (GameTableWindowButton opens it on demand).
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
            await root.stopGame()
        }
    }

}

#Preview(traits: .mockData) {
    let root = GameRoot.previewFixture(game: .player)
    PlayerGameScreen(
        root: root,
        playerController: PlayerController(root: root, asGameMaster: false)
    )
    .setAppSizeMode()
}
