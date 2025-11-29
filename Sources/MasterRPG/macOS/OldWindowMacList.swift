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

    @State private var selectionSheetLinkModel = SelectionSheetLinkModel()

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

        Group {
            Window("Character Generator", id: WindowIdentifier.generatorValueEditor.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.valueRoot.viewController.generatorEditorWindow(root: appModel.valueRoot)
                        .accentColor(NetworkModules.value.tint)
                        .tint(NetworkModules.value.tint)
                        .frame(minWidth: 600, minHeight: 400)
                        .environment(\.networkActions, appModel.gameRoot.networkActions())
                        .environment(\.valueActions, appModel.valueRoot.valueActions)
                        .environment(\.gameModus, appModel.settingsModel.gameModus)
                        .environment(\.showGame, appModel.settingsModel.showGame)
                        .environment(selectionSheetLinkModel)
                }
            }
            
            Window("Table Generator", id: WindowIdentifier.generatorTableEditor.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.tableRoot.viewController.generatorEditorWindow(root: appModel.tableRoot)
                        .accentColor(NetworkModules.table.tint)
                        .tint(NetworkModules.table.tint)
                        .frame(minWidth: 600, minHeight: 400)
                        .environment(\.networkActions, appModel.gameRoot.networkActions())
                        .environment(\.valueActions, appModel.valueRoot.valueActions)
                        .environment(\.gameModus, appModel.settingsModel.gameModus)
                        .environment(\.showGame, appModel.settingsModel.showGame)
                        .environment(selectionSheetLinkModel)
                }
            }
        }
        .defaultSize(CGSize(width: 600, height: 800))
        
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
