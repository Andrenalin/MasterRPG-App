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
        Window("Editor", id: WindowIdentifier.editor.rawValue) {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                RootView(appModel: appModel, editorOnly: true)
                    .setAppSizeMode()
                    .environmentSetUp(appModel)
                    .frame(minWidth: 600, minHeight: 400)
            }
        }
        .keyboardShortcut("E", modifiers: [.command, .shift, .option])
        
        MenuBarExtra() {
            MenuBarView(audioRoot: appModel.audioRoot)
        } label: {
            Label("MasterRPG", systemImage: "music.note.list")
        }
        .menuBarExtraStyle(.window)

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
