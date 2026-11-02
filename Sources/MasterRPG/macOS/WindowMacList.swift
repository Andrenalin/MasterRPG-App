// @copyright André Trettin

#if os(macOS)
import CoreRPG
import RolePlayGameKit
import SwiftUI
import CharacterRPG
import TableRPG
import GameRPG

struct WindowMacList: Scene {
    let appModel: AppModel

    var body: some Scene {
        MenuBarExtra() {
            MenuBarView(appModel: appModel)
                .environmentSetUp(appModel)
                .environmentActionSetUp(appModel)
                .appSettingsSetUp(appModel, handlesExternalEvents: false)
        } label: {
            Label {
                Text(verbatim: "MasterRPG")
            } icon: {
                Image(systemName: "music.note.list")
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                ManagedNavigationStack {
                    SettingsView(store: appModel)
                }
                .onNavigationRoute(WindowRouter(appModel: appModel, role: .settings))
                .onNavigationOpenURL(RootURLHandler(appModel: appModel, role: .settings))
                .navigationRoot(appModel.settingsNavigator)
                .environmentSetUp(appModel)
                .environmentActionSetUp(appModel)
                .modifier(UserSettingsViewModifier(appModel: appModel))
                .frame(minWidth: 600, minHeight: 400)
            }
        }
        .defaultSize(CGSize(width: 600, height: 800))
               
        BaseWindow("Player Game Screen", id: SceneId.gamePlayer.rawValue) {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                AppModeRouteType.gamePlayer
                    .frame(minWidth: 1000, minHeight: 600)
            }
            .sceneTracker(for: SceneId.gamePlayer)
            .environmentSetUp(appModel)
            .appSettingsSetUp(appModel)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultWindowPlacementAll(.leading(SceneId.game.rawValue))
        .restorationBehaviorAll(.disabled)
#if os(macOS)
        .keyboardShortcut("P", modifiers: [.command, .shift, .option])
#endif
    }
}

#endif
