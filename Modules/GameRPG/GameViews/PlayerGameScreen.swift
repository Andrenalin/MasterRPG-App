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
        let _ = Self.printViewChangesOnlyInDebug()

        ManagedNavigationStack {
            GameRootViewer(root: root, playerController: playerController, emptyTitle: "Game is running", contentType: .player)
        }
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
#if os(macOS)
        .overlay(alignment: .trailing) {
            if gameScreenModel.isSideMenuVisible {
                PlayerSideMenu(root: root)
                    .environment(gameScreenModel)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
#endif
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

#if os(macOS) || os(visionOS)
    #Preview(traits: .mockData) {
        PlayerSideMenu(root: .preview)
            .environment(AppSettingsModel())
            .environment(GameScreenModel())
            .environment(ScenesManager())
    }
#endif

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
            withAnimation { gameScreenModel.showMainTab = .none }

        case .inline:
            withAnimation { gameScreenModel.showMainTab = .value }

        case .window:
            withAnimation { gameScreenModel.showMainTab = .none }
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
                withAnimation { gameScreenModel.showSettingTab = .setting }
            } else {
                withAnimation { gameScreenModel.showMainTab = .value }
            }
#else
            withAnimation { gameScreenModel.showMainTab = .value }
#endif
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
private struct PlayerSideMenu: View {
    let root: GameRoot

    private static let modules: [NetworkModules] = [
        .value,
        .table,
        .audio,
        .photo,
        .pdf,
        .space,
        .dice
    ]

    var body: some View {
        GlassEffectContainerAll {
            VStack(spacing: 8) {
                if root.gameModel.gameType != .observer {
                    PlayerGameWindowButtonView(root: root)
                }

                ForEach(Self.modules, id: \.self) { module in
                    GameWindowButtonView(
                        title: module.title,
                        systemImage: module.icon,
                        tint: module.tint,
                        sceneId: SceneId.sceneId(for: module)
                    )
                }
            }
        }
#if os(macOS)
        .padding(.trailing, 8)
#else
        .padding()
#endif
    }
}

private struct PlayerGameWindowButtonView: View {
    let root: GameRoot

    @Environment(AppSettingsModel.self) private var appSettingsModel
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        let isWindowPresented = scenesManager.getSceneState(for: gameWindowScene).isPresentedInGameMenu

        Button(NetworkModules.game.title, systemImage: NetworkModules.game.icon) {
            toggleGameWindow(isPresented: isWindowPresented)
        }
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .padding(8)
        .contentShape(.circle)
        .modifier(
            GameWindowButtonAppearance(
                tint: NetworkModules.game.tint,
                isWindowPresented: isWindowPresented
            )
        )
        .help(NetworkModules.game.title)
        .accessibilityValue(
            Text(isWindowPresented ? "Window open" : "Window closed", bundle: .module)
        )
        .disabled(root.gameModel.selectedCharacter == nil && !isWindowPresented)
    }

    private var gameWindowScene: SceneId {
        SceneId.viewerId(for: .value)
    }

    private func toggleGameWindow(isPresented: Bool) {
        if isPresented {
            scenesManager.dismissWindow(gameWindowScene)
            gameScreenModel.gameMainTabDisplayMode = .hidden
            appSettingsModel.playerMainTabDisplayMode = GameMainTabDisplayMode.hidden.rawValue
        } else if let characterId = root.gameModel.selectedCharacter {
            withAnimation {
                gameScreenModel.showMainTab = .none
                gameScreenModel.gameMainTabDisplayMode = .window
            }
            appSettingsModel.playerMainTabDisplayMode = GameMainTabDisplayMode.window.rawValue
            scenesManager.openWindow(
                gameWindowScene,
                selection: WindowItemSelection(itemId: characterId)
            )
        }
    }
}
#endif

private struct PlayerOverlayMenu: View {
    let root: GameRoot
    let playerController: PlayerController

    var body: some View {
        OverlayGameLayout(root: root, hideDice: root.gameModel.gameType == .observer) {
#if os(visionOS) || os(macOS)
            EmptyView()
#else
            OverlayGameMenu(root: root, playerController: playerController, isMaster: false)
#endif
        } sideOverlay: {
            OverlayPlayerTabBar(root: root)
        } toolBarOverlay: {
            OverlayToolBar(root: root, playerController: playerController, isMaster: false)
        }
#if os(macOS)
        .toolbar {
            GameToolbarContent(root: root, role: .player, playerController: playerController)
        }
#endif
        .padding(.leading, valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
        .id("playerOverlayLayout")
    }
}

#Preview(traits: .mockData) {
    PlayerGameScreen(root: .preview, playerController: PlayerController.preview)
        .environment(GameScreenModel())
}

#Preview {
    PlayerOverlayMenu(root: .preview, playerController: .preview)
        .environment(GameScreenModel())
}
