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

    @State private var gameScreenModel = GameScreenModel()
    @State private var diceShowOptionModel = DiceDisplayModel()

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        ManagedNavigationStack {
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
            if gameScreenModel.isSideMenuVisible {
                MasterSideMenu(adventureId: adventureId)
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

#if os(macOS) || os(visionOS)
    #Preview(traits: .mockData) {
        MasterSideMenu(adventureId: UUID())
            .environment(AppSettingsModel())
            .environment(GameScreenModel())
            .environment(ScenesManager())
    }
#endif

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
            withAnimation { gameScreenModel.showMainTab = .none }
            scenesManager.openWindow(
                SceneId.viewerId(for: .adventure),
                selection: WindowItemSelection(itemId: adventureId)
            )
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

private struct MasterSideMenu: View {
    let adventureId: UUID

    var body: some View {
        MasterModuleWindowMenu(adventureId: adventureId)
    }
}

private struct MasterModuleWindowMenu: View {
    let adventureId: UUID

    private static let modules: [NetworkModules] = [
        .game,
        .adventure,
        .audio,
        .dice,
        .map,
        .pdf,
        .photo,
        .space,
        .table,
        .value,
        .weather
    ]

    var body: some View {
        GlassEffectContainerAll {
            VStack(spacing: 8) {
                ForEach(Self.modules, id: \.self) { module in
                    if module == .game {
                        MasterGameWindowButtonView(adventureId: adventureId)
                    } else {
                        MasterModuleWindowButtonView(valueType: module)
                    }
                }

                GameWindowButtonView(
                    title: String(localized: "Logs", bundle: .module),
                    systemImage: "doc.text.magnifyingglass",
                    tint: NetworkModules.game.tint,
                    sceneId: .logs
                )
            }
        }
#if os(macOS)
        .padding(.trailing, 8)
#else
        .padding()
#endif
    }
}

private struct MasterGameWindowButtonView: View {
    let adventureId: UUID

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
    }

    private var gameWindowScene: SceneId {
        SceneId.viewerId(for: .adventure)
    }

    private func toggleGameWindow(isPresented: Bool) {
        if isPresented {
            scenesManager.dismissWindow(gameWindowScene)
            gameScreenModel.gameMainTabDisplayMode = .hidden
            appSettingsModel.masterMainTabDisplayMode = GameMainTabDisplayMode.hidden.rawValue
        } else {
            withAnimation {
                gameScreenModel.showMainTab = .none
                gameScreenModel.gameMainTabDisplayMode = .window
            }
            appSettingsModel.masterMainTabDisplayMode = GameMainTabDisplayMode.window.rawValue
            scenesManager.openWindow(
                gameWindowScene,
                selection: WindowItemSelection(itemId: adventureId)
            )
        }
    }
}

private struct MasterModuleWindowButtonView: View {
    let valueType: NetworkModules

    var body: some View {
        GameWindowButtonView(
            title: valueType.title,
            systemImage: valueType.icon,
            tint: valueType.tint,
            sceneId: SceneId.sceneId(for: valueType)
        )
    }
}

struct GameWindowButtonView: View {
    let title: String
    let systemImage: String
    let tint: Color
    let sceneId: SceneId

    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        let isWindowPresented = scenesManager.getSceneState(for: sceneId).isPresentedInGameMenu

        Button(title, systemImage: systemImage) {
            toggleWindow(sceneId, isPresented: isWindowPresented)
        }
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .padding(8)
        .contentShape(.circle)
        .modifier(
            GameWindowButtonAppearance(
                tint: tint,
                isWindowPresented: isWindowPresented
            )
        )
        .help(title)
        .accessibilityValue(
            Text(isWindowPresented ? "Window open" : "Window closed", bundle: .module)
        )
    }

    private func toggleWindow(_ sceneId: SceneId, isPresented: Bool) {
        withAnimation(.easeInOut) {
            if isPresented {
                scenesManager.dismissWindow(sceneId)
            } else {
                scenesManager.openWindow(sceneId)
            }
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

struct GameWindowButtonAppearance: ViewModifier {
    let tint: Color
    let isWindowPresented: Bool

    func body(content: Content) -> some View {
#if os(visionOS)
        content
            .buttonStyle(.bordered)
            .tint(isWindowPresented ? tint : .accentColor)
            .background(
                isWindowPresented ? tint.opacity(0.35) : Color.clear,
                in: .circle
            )
#else
        let glass: Glass = if isWindowPresented {
            .regular.tint(tint.opacity(0.7)).interactive()
        } else {
            .regular.interactive()
        }

        content
            .buttonStyle(.plain)
            .glassEffect(glass, in: .circle)
#endif
    }
}

private struct MasterOverlayMenu: View {
    let root: GameRoot
    let adventureId: UUID
    let playerController: PlayerController

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        OverlayGameLayout(root: root, hideDice: false) {
#if os(visionOS) || os(macOS)
            EmptyView()
#else
            OverlayGameMenu(root: root, playerController: nil, isMaster: true)
#endif
        } sideOverlay: {
            OverlayMasterTabBar(root: root, adventureId: adventureId)
        } toolBarOverlay: {
            OverlayToolBar(root: root, playerController: playerController, isMaster: true)
        }
#if os(macOS)
        .toolbar {
            GameToolbarContent(root: root, role: .master, playerController: nil)
        }
#endif

        .padding(.leading, valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
        .id("masterOverlayLayout")
    }
}

#Preview("iPad") {
    MasterGameScreen(root: .preview, playerController: .preview, adventureId: UUID())
}

#Preview("MacMenu") {
    ZStack(alignment: .trailing) {
        NetworkModules.map.color
        MasterSideMenu(adventureId: UUID())
    }
    .environment(AppSettingsModel())
    .environment(GameScreenModel())
    .environment(ScenesManager())
}

#Preview {
    MasterOverlayMenu(root: .preview, adventureId: UUID(), playerController: .preview)
        .environment(GameScreenModel())
}
