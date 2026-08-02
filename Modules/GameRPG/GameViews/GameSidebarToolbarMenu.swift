// @copyright André Trettin

#if os(macOS)
import CoreRPG
import SwiftUI

struct GameSidebarToolbarMenu: View {
    let role: GameToolbarRole

    @Environment(AppSettingsModel.self) private var appSettingsModel
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Menu {
            Toggle(isOn: gameSidebarBinding) {
                Label {
                    Text("Game Sidebar", bundle: .module)
                } icon: {
                    Image(systemName: NetworkModules.game.icon)
                }
            }

            Button {
                withAnimation(accessibilityReduceMotion ? nil : .default) {
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
            .disabled(!isSidebarVisible)

            Button(action: toggleSideMenuButtons) {
                Label {
                    Text(
                        gameScreenModel.isSideMenuVisible
                            ? "Hide Side Menu Buttons"
                            : "Show Side Menu Buttons",
                        bundle: .module
                    )
                } icon: {
                    Image(systemName: "sidebar.right")
                        .symbolVariant(gameScreenModel.isSideMenuVisible ? .fill : .none)
                }
            }

            Divider()

            if role == .master {
                Toggle(isOn: battleRoundBinding) {
                    Label {
                        Text("Battle Round", bundle: .module)
                    } icon: {
                        Image(systemName: "shield.lefthalf.filled")
                    }
                }
            }
        } label: {
            Label {
                Text("Game View", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.game.icon)
                    .symbolVariant(isSidebarVisible ? .fill : .none)
            }
            .labelStyle(.iconOnly)
        }
        .help(Text("Game View Menu", bundle: .module))
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
            set: { isVisible in
                setGameSidebarVisible(isVisible)
            }
        )
    }

    private var battleRoundBinding: Binding<Bool> {
        Binding(
            get: {
                scenesManager.getSceneState(for: .battleRound).isPresentedInGameMenu
            },
            set: { isVisible in
                withAnimation(accessibilityReduceMotion ? nil : .easeInOut) {
                    if isVisible {
                        scenesManager.openWindow(.battleRound)
                    } else {
                        scenesManager.dismissWindow(.battleRound)
                    }
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

        withAnimation(accessibilityReduceMotion ? nil : .default) {
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

    private func toggleSideMenuButtons() {
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            gameScreenModel.isSideMenuVisible.toggle()
        }
    }
}

#Preview {
    GameSidebarToolbarMenu(role: .master)
        .environment(AppSettingsModel())
        .environment(GameScreenModel())
        .environment(ScenesManager())
}
#endif
