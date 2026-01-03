// @copyright André Trettin

#if os(macOS)
import CoreRPG
import RolePlayGameKit
import SwiftUI
import CharacterRPG
import TableRPG
import GameRPG


struct OldWindowMacList: Scene {
    let appModel: AppModel

    var body: some Scene {
        WindowGroup("Editor", id: WindowIdentifier.additionalEditor.rawValue) {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                RootView(appModel: appModel, editorOnly: true)
                    .environment(appModel.optionKeyDownModel)
                    .environment(appModel.settingsModel)
                    .frame(minWidth: 600, minHeight: 400)
            }
        }
        .defaultSize(CGSize(width: 1000, height: 800))

        Settings {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                SettingsView(store: appModel)
                    .environment(appModel.settingsModel)
                    .accentColor(.teal)
                    .tint(.teal)
                    .frame(minWidth: 600, minHeight: 400)
            }
        }
        .defaultSize(CGSize(width: 600, height: 800))
    }
}

#endif
