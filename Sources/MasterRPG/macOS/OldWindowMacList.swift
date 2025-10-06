// @copyright André Trettin

#if os(macOS)
import AndrenalinKit
import RoleGameKit
import SwiftUI
import RPGValues
import RPGTables
import RPGGame


struct OldWindowMacList: Scene {
    let appStore: AppStore

    @State private var selectionSheetLinkModel = SelectionSheetLinkModel()

    var body: some Scene {
        WindowGroup("Editor", id: WindowIdentifier.additionalEditor.rawValue) {
            DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                RootView(appStore: appStore, editorOnly: true)
                    .environment(appStore.optionKeyDownModel)
                    .environment(appStore.settingsModel)
                    .frame(minWidth: 600, minHeight: 400)
            }
        }
        .defaultSize(CGSize(width: 1000, height: 800))

        Group {
            Window("Character Generator", id: WindowIdentifier.generatorValueEditor.rawValue) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.valueRoot.viewController.generatorEditorWindow()
                        .accentColor(.teal)
                        .tint(.teal)
                        .frame(minWidth: 600, minHeight: 400)
                        .environment(\.networkActions, appStore.gameRoot.networkActions())
                        .environment(\.valueActions, appStore.valueRoot.valueActions)
                        .environment(\.gameModus, appStore.settingsModel.gameModus)
                        .environment(\.showGame, appStore.settingsModel.showGame)
                        .environment(selectionSheetLinkModel)
                }
            }
            
            Window("Table Generator", id: WindowIdentifier.generatorTableEditor.rawValue) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.tableRoot.viewController.generatorEditorWindow()
                        .accentColor(.teal)
                        .tint(.teal)
                        .frame(minWidth: 600, minHeight: 400)
                        .environment(\.networkActions, appStore.gameRoot.networkActions())
                        .environment(\.valueActions, appStore.valueRoot.valueActions)
                        .environment(\.gameModus, appStore.settingsModel.gameModus)
                        .environment(\.showGame, appStore.settingsModel.showGame)
                        .environment(selectionSheetLinkModel)
                }
            }
        }
        .defaultSize(CGSize(width: 600, height: 800))
        
        Settings {
            DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                SettingsView(store: appStore)
                    .environment(appStore.settingsModel)
                    .accentColor(.teal)
                    .tint(.teal)
                    .frame(minWidth: 600, minHeight: 400)
            }
        }
        .defaultSize(CGSize(width: 600, height: 800))
    }
}

#endif
