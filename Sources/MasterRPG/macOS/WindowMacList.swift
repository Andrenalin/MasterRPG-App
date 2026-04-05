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
        } label: {
            Label("MasterRPG", systemImage: "music.note.list")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                ManagedNavigationStack {
                    SettingsView(store: appModel)
                }
                .environmentSetUp(appModel)
                .accentColor(.blue)
                .tint(.teal)
                .frame(minWidth: 600, minHeight: 400)
            }
        }
        .defaultSize(CGSize(width: 600, height: 800))
    }
}

#endif
