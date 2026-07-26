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
        .onDisappear {
            root.mapRoot.rootModel.clearGameEditorSession()
        }
        .persistGameDiceVisibility(
            gameScreenModel: gameScreenModel,
            diceDisplayModel: diceShowOptionModel
        )
#if os(visionOS)
        .gameImmersiveSpaceSync(root: root)
        .ornament(attachmentAnchor: .scene(.topLeading), contentAlignment: .topTrailing) {
            root.diceRoot.viewController.dicePlayerView(root: root.diceRoot)
                .environment(diceShowOptionModel)
        }
        .ornament(attachmentAnchor: .scene(.topTrailing), contentAlignment: .bottomTrailing) {
            OverlayGameMenu(root: root, playerController: playerController, isMaster: false)
                .environment(diceShowOptionModel)
                .environment(gameScreenModel)
                .padding(.bottom, 12)
        }
        .ornament(attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
            VStack {
                PlayerSideMenu(root: root)
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

private extension PlayerGameScreen {
    func prepareWindows() async {
        do {
            try await Task.sleep(for: .seconds(0.6))
        } catch {
            return
        }

#if os(macOS) || os(visionOS)
        let savedMode = GameMainTabDisplayMode(rawValue: appSettingsModel.playerMainTabDisplayMode) ?? .hidden
        gameScreenModel.gameMainTabDisplayMode = savedMode

        switch savedMode {
        case .hidden:
            withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.showMainTab = .none }

        case .inline:
            withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.showMainTab = .value }

        case .window:
            withAnimation(accessibilityReduceMotion ? nil : .default) { gameScreenModel.showMainTab = .none }
            if let characterId = root.gameModel.selectedCharacter {
                scenesManager.openWindow(SceneId.viewerId(for: .value), selection: WindowItemSelection(itemId: characterId))
            }
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

#Preview(traits: .mockData) {
    let root = GameRoot.previewFixture(game: .player)
    PlayerGameScreen(
        root: root,
        playerController: PlayerController(root: root, asGameMaster: false)
    )
    .setAppSizeMode()
}
