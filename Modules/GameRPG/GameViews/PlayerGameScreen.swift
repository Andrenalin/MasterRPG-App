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
    
    @State private var gameScreenModel = GameScreenModel()
    @State private var infoState: NetworkModules = .none
    
#if os(macOS) || os(visionOS)
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
#endif
    
    @Environment(ScenesManager.self) private var sceneManager

    @State private var diceShowOptionModel = DiceDisplayModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            GameRootViewer(root: root, playerController: playerController, emptyTitle: "Game is running") { _ in
                root.mapRoot.viewController.gameMapView(root: root.mapRoot, playerId: root.gameModel.gameConfig.id)
            }
            
            overlayMenu
        }
        .focusSectionAll()
        .alert(Text("Quit Game?", bundle: .module), isPresented: $gameScreenModel.showQuitGameAlert) {
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
#if os(visionOS)
        .onChange(of: root.networkStore.sharePlayStore.switchToImmersive) {
            Task {
                if root.networkStore.sharePlayStore.switchToImmersive {
                    await openImmersiveSpace(id: SceneId.spaceViewer.rawValue, value: ItemSelection(itemId: root.spaceRoot.gameControllable.currentId, entryId: nil))
                } else {
                    await dismissImmersiveSpace()
                }
            }
        }
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

private extension PlayerGameScreen {
    func prepareWindows() {
#if os(iOS) || os(visionOS)
        Task {
            try? await Task.sleep(for: .seconds(0.1))
            gameScreenModel.showGameType <=> .table
            withAnimation { gameScreenModel.showMainTab <=> .game }
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation { gameScreenModel.showGameType <=> .value }
        }
#elseif os(macOS)
        Task {
            try? await Task.sleep(for: .seconds(0.1))
            withAnimation { gameScreenModel.showMainTab <=> .game }
        }
#endif
#if os(visionOS)
        Task {
            try? await Task.sleep(for: .seconds(0.15))
            showWindow(for: .table)
            try? await Task.sleep(for: .seconds(0.15))
            showWindow(for: .pdf)
            try? await Task.sleep(for: .seconds(0.15))
            showWindow(for: .value)
        }
#endif
    }

    var overlayMenu: some View {
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

#Preview {
    PlayerGameScreen(root: .preview, playerController: PlayerController.preview)
        .environment(GameScreenModel())
}
