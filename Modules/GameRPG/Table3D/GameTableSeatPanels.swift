// @copyright André Trettin

#if os(visionOS)
import AudioRPG
import CoreRPG
import DiceRPG
import MapRPG
import SwiftUI

/// Reports a seat panel's size to the model, in meters, which stands the panel beside the dice
/// and raises it by half its own height.
private struct ReportsSeatPanelSize: ViewModifier {
    let game: GameTableModel
    let panel: TableSeatPanel

    @Environment(\.physicalMetrics) private var physicalMetrics

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            game.seatPanelSizeChanged(
                SIMD2<Float>(
                    Float(physicalMetrics.convert(size.width, to: .meters)),
                    Float(physicalMetrics.convert(size.height, to: .meters))
                ),
                for: panel
            )
        }
    }
}

/// The glass a seat panel stands on.
private struct SeatPanelGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fixedSize()
            .padding()
            .glassBackgroundEffect(in: .rect(cornerRadius: 28))
    }
}

extension TableSeatGroup {
    /// The window buttons of a windows group, in display order; empty for the controls group.
    /// A role only gets the windows it has the modules for.
    var windowModules: [NetworkModules] {
        switch self {
        case .controls: []
        case .windowsOne: [.game, .map, .photo, .audio, .weather, .space]
        case .windowsTwo: [.table, .pdf, .value, .adventure, .dice, .rule]
        }
    }

    var systemImage: String {
        switch self {
        case .controls: "slider.horizontal.3"
        case .windowsOne: "macwindow"
        case .windowsTwo: "macwindow.on.rectangle"
        }
    }

    var title: String {
        switch self {
        case .controls: String(localized: "Game Controls", bundle: .module)
        case .windowsOne: String(localized: "Game Windows", bundle: .module)
        case .windowsTwo: String(localized: "More Windows", bundle: .module)
        }
    }

    /// The color the dock button takes.
    var module: NetworkModules {
        switch self {
        case .controls: .setting
        case .windowsOne: .game
        case .windowsTwo: .value
        }
    }
}

/// The dock: three buttons that behave like radio buttons. One opens its group's panel above the
/// dock and closes the one that was open; the open group's own button closes it. The table's
/// notices stand under them.
@MainActor
struct GameSeatDockPanel: View {
    let game: GameTableModel

    var body: some View {
        VStack(alignment: .leading) {
            GlassEffectContainerAll {
                HStack {
                    ForEach(TableSeatGroup.allCases, id: \.self) { group in
                        Button {
                            game.toggleSeatGroup(group)
                        } label: {
                            Label {
                                Text(verbatim: group.title)
                            } icon: {
                                Image(systemName: group.systemImage)
                            }
                        }
                        .selectedRoundButton(
                            title: group.title,
                            module: group.module,
                            isSelected: game.openSeatGroup == group
                        )
                        .accessibilityValue(Text(game.openSeatGroup == group ? "Open" : "Closed", bundle: .module))
                    }
                }
            }
            GameTableNoticesView(game: game)
                .frame(maxWidth: 320, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(SeatPanelGlass())
        .modifier(ReportsSeatPanelSize(game: game, panel: .dock))
    }
}

/// The panel of one control group, open above the dock while its button is pressed.
@MainActor
struct GameSeatGroupPanel: View {
    let root: GameRoot
    let game: GameTableModel
    let group: TableSeatGroup
    let gameScreenModel: GameScreenModel

    var body: some View {
        ZStack {
            if game.openSeatGroup == group {
                content
                    .environment(gameScreenModel)
                    .modifier(SeatPanelGlass())
            }
        }
        // Outside the condition: a closed panel reports no size.
        .modifier(ReportsSeatPanelSize(game: game, panel: group.panel))
    }

    @ViewBuilder
    private var content: some View {
        let isMaster = root.gameModel.gameConfig.isMaster
        switch group {
        case .controls:
            HStack {
                GameSeatQuitButton(root: root, isMaster: isMaster)
                GameSeatConnectionButton(root: root, isMaster: isMaster)
                if root.offersTablePlayers(isMaster: isMaster) {
                    TablePlayersButton(root: root)
                }
                if isMaster {
                    root.audioRoot.viewController.toolbarVolumeButton(root: root.audioRoot, showsPlayer: true)
                        .tint(Color.accentColor)
                        .frame(minWidth: 44, minHeight: 44)
                } else {
                    root.audioRoot.viewController.viewVolume(root: root.audioRoot, alignment: .top)
                }
            }
        case .windowsOne, .windowsTwo:
            GameSeatWindowButtons(root: root, isMaster: isMaster, modules: group.windowModules)
        }
    }
}

/// A row of module window buttons, of the modules this role has.
@MainActor
private struct GameSeatWindowButtons: View {
    let root: GameRoot
    let isMaster: Bool
    let modules: [NetworkModules]

    var body: some View {
        // The game window button is the role's own (adventure or character sheet), whatever the list.
        let available = isMaster ? NetworkModules.gameWindowMasterModules : NetworkModules.gameWindowPlayerModules
        GlassEffectContainerAll {
            HStack {
                ForEach(modules.filter { $0 == .game || available.contains($0) }, id: \.self) { module in
                    if module == .game {
                        WindowOpenButton(root: root)
                    } else if isMaster {
                        MasterModuleWindowButtonView(valueType: module)
                    } else {
                        GameWindowButtonView(
                            title: module.title,
                            systemImage: module.icon,
                            module: module,
                            sceneId: SceneId.sceneId(for: module)
                        )
                    }
                }
            }
        }
    }
}

/// Leaves the game, after a confirmation, and returns to the start window. (The game master's
/// "Save and Quit" lives in the 2D game window, which visionOS does not show during a game.)
@MainActor
private struct GameSeatQuitButton: View {
    let root: GameRoot
    let isMaster: Bool

    @Environment(ScenesManager.self) private var scenesManager
    @Environment(AppGameStateModel.self) private var appGameStateModel: AppGameStateModel?
    @State private var isConfirming = false

    var body: some View {
        Button {
            isConfirming = true
        } label: {
            Label {
                Text("Quit", bundle: .module)
            } icon: {
                Image(systemName: "xmark.circle")
            }
        }
        .labelStyle(.iconOnly)
        .frame(minWidth: 44, minHeight: 44)
        .alert(Text("Quit Game?", bundle: .module), isPresented: $isConfirming) {
            Button {
                let controller = GameTablePresentationController(
                    root: root, scenesManager: scenesManager, appGameStateModel: appGameStateModel
                )
                Task { await controller.endGame() }
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
    }
}

/// The connection status, and the join code behind it.
@MainActor
private struct GameSeatConnectionButton: View {
    let root: GameRoot
    let isMaster: Bool

    var body: some View {
        let playerController = isMaster ? nil : root.gameModel.playerController
        GameJoinCodeRevealButton(
            root: root,
            isMaster: isMaster,
            connectionStatus: playerController.map {
                GameConnectionStatusPresentation(
                    lostMaster: $0.gameModel.lostMaster,
                    sharePlayState: root.networkStore.sharePlayStore.connectionState,
                    isReconnecting: root.isLocalNetworkReconnecting
                )
            } ?? root.hostingStatus(isMaster: isMaster)
        )
    }
}

/// The game master's one button for the map controls, at the end of the map: opens and closes
/// the panel above it, which opens by itself when the first map is shown.
@MainActor
struct GameSeatMapDockPanel: View {
    let root: GameRoot
    let game: GameTableModel

    var body: some View {
        ZStack {
            if game.isGameMaster, game.currentMapId != nil || hasWeather(root: root, game: game) {
                GlassEffectContainerAll {
                    Button {
                        game.toggleMapControls()
                    } label: {
                        Label {
                            Text(verbatim: Self.title)
                        } icon: {
                            Image(systemName: "slider.horizontal.below.rectangle")
                        }
                    }
                    .selectedRoundButton(
                        title: Self.title,
                        module: .map,
                        isSelected: game.isMapControlsOpen
                    )
                    .accessibilityValue(Text(game.isMapControlsOpen ? "Open" : "Closed", bundle: .module))
                }
                .modifier(SeatPanelGlass())
            }
        }
        .modifier(ReportsSeatPanelSize(game: game, panel: .mapDock))
    }

    private static var title: String { String(localized: "Map Controls", bundle: .module) }
}

/// Whether the game master has weather on the tables, which has its own button to clear.
@MainActor
private func hasWeather(root: GameRoot, game: GameTableModel) -> Bool {
    game.isGameMaster && root.gameModel.playerController?.gameModel.tableWeather.shownWeatherId != nil
}

/// The map controls: the shared map toolbar, as a row with its own collapse button, and the
/// button that clears the weather. Open above the map dock.
@MainActor
struct GameSeatMapPanel: View {
    let root: GameRoot
    let game: GameTableModel
    let gameScreenModel: GameScreenModel

    var body: some View {
        ZStack {
            if game.isGameMaster, game.isMapControlsOpen,
               game.currentMapId != nil || hasWeather(root: root, game: game) {
                HStack(alignment: .top) {
                    if game.currentMapId != nil {
                        game.mapRoot.viewController.gameToolBarView(
                            root: game.mapRoot,
                            isMaster: game.isGameMaster,
                            session: game
                        )
                    }
                    if hasWeather(root: root, game: game) {
                        GameTableClearWeatherButton(root: root)
                    }
                }
                .environment(gameScreenModel)
                .modifier(SeatPanelGlass())
            }
        }
        // Outside the condition: a closed panel reports no size.
        .modifier(ReportsSeatPanelSize(game: game, panel: .map))
    }
}
#endif
