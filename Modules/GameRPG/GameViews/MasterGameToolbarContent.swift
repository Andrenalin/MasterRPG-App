// @copyright André Trettin

#if os(macOS)
import AudioRPG
import CoreRPG
import Foundation
import SwiftUI

enum GameToolbarRole: Equatable {
    case master
    case player
}

struct GameToolbarContent: ToolbarContent {
    let root: GameRoot
    let role: GameToolbarRole
    let playerController: PlayerController?

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if role == .master || root.gameModel.gameType != .observer {
                GameDiceToggleButton()
            }

            GameElapsedTimerText(startDate: root.gameModel.startGameTime)
        }

        ToolbarItemGroup(placement: .principal) {
            root.audioRoot.viewController.toolbarVolumeButton(root: root.audioRoot)

            if let playerController {
                PlayerConnectionStatusView(playerController: playerController)
            }
        }

        if role == .master || root.gameModel.gameType != .observer {
            ToolbarItem(placement: .automatic) {
                GameSidebarToolbarMenu(role: role)
            }
        }

        ToolbarSpacer(.fixed, placement: .automatic)

        ToolbarItem(placement: .automatic) {
            GameQuitToolbarButton()
        }
    }
}

private struct GameElapsedTimerText: View {
    let startDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(
                elapsedDuration(at: context.date),
                format: .time(pattern: .hourMinuteSecond(padHourToLength: 2))
            )
            .monospacedDigit()
            .padding(.horizontal)
        }
    }

    private func elapsedDuration(at date: Date) -> Duration {
        let elapsedSeconds = max(0, date.timeIntervalSince(startDate)).rounded(.down)
        return .seconds(elapsedSeconds)
    }
}

private struct GameSidebarToolbarMenu: View {
    let role: GameToolbarRole

    @Environment(AppSettingsModel.self) private var appSettingsModel
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        Menu {
            Toggle(isOn: gameSidebarBinding) {
                Label {
                    Text("Game Sidebar", bundle: .module)
                } icon: {
                    Image(systemName: NetworkModules.game.icon)
                }
            }

            if isSidebarVisible {
                Button {
                    withAnimation {
                        gameScreenModel.toggleSideBarWidth()
                    }
                } label: {
                    Label {
                        Text(
                            gameScreenModel.isLargeSideBar ? "Reduce Game Sidebar" : "Enlarge Game Sidebar",
                            bundle: .module
                        )
                    } icon: {
                        Image(
                            systemName: gameScreenModel.isLargeSideBar
                                ? "square.resize.down"
                                : "square.resize.up"
                        )
                    }
                }
            }

            Toggle(isOn: sideMenuBinding) {
                Label {
                    Text("Side Menu", bundle: .module)
                } icon: {
                    Image(systemName: "sidebar.right")
                }
            }
            .disabled(!isSidebarVisible)
        } label: {
            Label {
                Text("Game Sidebar", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.game.icon)
                    .symbolVariant(isSidebarVisible ? .fill : .none)
            }
            .labelStyle(.iconOnly)
        }
        .help(
            Text(
                isSidebarVisible ? "Hide Game Sidebar" : "Show Game Sidebar",
                bundle: .module
            )
        )
    }

    private var inlineModule: NetworkModules {
        role == .master ? .game : .value
    }

    private var windowModule: NetworkModules {
        role == .master ? .adventure : .value
    }

    private var isSidebarVisible: Bool {
        gameScreenModel.showMainTab == inlineModule
    }

    private var gameSidebarBinding: Binding<Bool> {
        Binding(
            get: { isSidebarVisible },
            set: { isVisible in setGameSidebarVisible(isVisible) }
        )
    }

    private var sideMenuBinding: Binding<Bool> {
        Binding(
            get: { gameScreenModel.isSideMenuVisible },
            set: { isVisible in
                guard isSidebarVisible || isVisible else { return }
                withAnimation {
                    gameScreenModel.isSideMenuVisible = isVisible
                }
            }
        )
    }

    private func setGameSidebarVisible(_ isVisible: Bool) {
        let nextMode: GameMainTabDisplayMode = isVisible ? .inline : .hidden

        if nextMode == .inline {
            let gameWindowScene = SceneId.viewerId(for: windowModule)
            switch scenesManager.getSceneState(for: gameWindowScene) {
            case .opening, .opened:
                scenesManager.dismissWindow(gameWindowScene)
            case .closing, .closed:
                break
            }
        }

        withAnimation {
            gameScreenModel.showMainTab = nextMode == .inline ? inlineModule : .none
            gameScreenModel.gameMainTabDisplayMode = nextMode
        }

        switch role {
        case .master:
            appSettingsModel.masterMainTabDisplayMode = nextMode.rawValue
        case .player:
            appSettingsModel.playerMainTabDisplayMode = nextMode.rawValue
        }
    }
}

private struct PlayerConnectionStatusView: View {
    let playerController: PlayerController

    var body: some View {
        Label {
            Text(
                playerController.gameModel.lostMaster ? "Connection Lost" : "Connected",
                bundle: .module
            )
        } icon: {
            Image(systemName: playerController.gameModel.lostMaster ? "wifi.slash" : "wifi")
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(playerController.gameModel.lostMaster ? .red : .teal)
        .help(
            Text(
                playerController.gameModel.lostMaster ? "Connection Lost" : "Connected",
                bundle: .module
            )
        )
    }
}

private struct GameQuitToolbarButton: View {
    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        Button {
            gameScreenModel.showQuitGameAlert = true
        } label: {
            Label {
                Text("Quit", bundle: .module)
            } icon: {
                Image(systemName: "xmark.circle")
            }
            .labelStyle(.iconOnly)
        }
        .help(Text("Quit", bundle: .module))
    }
}
#endif
