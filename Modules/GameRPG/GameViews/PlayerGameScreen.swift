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

    @State private var gameScreenModel = GameScreenModel()
    @State private var diceShowOptionModel = DiceDisplayModel()

    var body: some View {
        GameRootViewer(root: root, playerController: playerController, emptyTitle: "Game is running", contentType: .player)
        .overlay(alignment: .topLeading) {
            PlayerOverlayMenu(root: root, playerController: playerController)
                .environment(diceShowOptionModel)
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
#if os(visionOS)
        .modifier(ImmersiveSpaceHandler(root: root))
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
                PlayerMenuView()
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

        let savedMode = GameMainTabDisplayMode(rawValue: appSettingsModel.playerMainTabDisplayMode) ?? .hidden
        gameScreenModel.gameMainTabDisplayMode = savedMode

        switch savedMode {
        case .hidden:
            withAnimation { gameScreenModel.showMainTab = .none }

        case .inline:
            withAnimation { gameScreenModel.showMainTab = .value }

        case .window:
#if os(macOS) || os(visionOS)
            if let characterId = root.gameModel.selectedCharacter {
                scenesManager.openWindow(SceneId.viewerId(for: .value), selection: WindowItemSelection(itemId: characterId))
            }
#endif
        }

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

#if os(visionOS)
private struct ImmersiveSpaceHandler: ViewModifier {
    let root: GameRoot

    @Environment(ScenesManager.self) private var scenesManager

    func body(content: Content) -> some View {
        content.task(id: root.networkStore.sharePlayStore.switchToImmersive) {
            if root.networkStore.sharePlayStore.switchToImmersive {
                await scenesManager.openSpaceViewer(selection: ItemSelection(itemId: root.spaceRoot.gameControllable.currentId, entryId: nil))
            } else {
                await scenesManager.dismissSpaceViewer()
            }
        }
    }
}

private struct PlayerMenuView: View {
    @Environment(ScenesManager.self) private var scenesManager
    @State private var infoState: NetworkModules = .none

    var body: some View {
        Group {
            GameToolBarButtonView(valueType: .value, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .table, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .audio, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .photo, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .pdf, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .space, alwaysSet: true, showType: $infoState)
            GameToolBarButtonView(valueType: .dice, alwaysSet: true, showType: $infoState)
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

private struct PlayerOverlayMenu: View {
    let root: GameRoot
    let playerController: PlayerController

    var body: some View {
        OverlayGameLayout(root: root, hideDice: root.gameModel.gameConfig.type == .observer) {
#if os(visionOS)
            EmptyView()
#else
            OverlayGameMenu(root: root, playerController: playerController, isMaster: false)
#endif
        } sideOverlay: {
            OverlayPlayerTabBar(root: root)
        } toolBarOverlay: {
            OverlayToolBar(root: root, playerController: playerController, isMaster: false)
        }
        .padding([.top, .leading], valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
    }
}

#Preview(traits: .mockData) {
    PlayerGameScreen(root: .preview, playerController: PlayerController.preview)
        .environment(GameScreenModel())
}
