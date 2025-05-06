// @copyright André Trettin

#if os(visionOS) || os(macOS)
import AndrenalinKit
import RoleGameKit
import SwiftUI
import RPGAdventures
import RPGMaps
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGValues
import RPGPhotos
import RPGWeathers
import RPGTables

struct WindowMacVisionList: Scene {
    let appStore: AppStore
    
    var body: some Scene {
        Group {
            WindowGroup("Adventure Viewer", id: WindowIdentifier.adventureViewer.rawValue, for: ItemSelection.self) { $selection in
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.adventureRoot.viewController.adventureWindow(selection: selection ?? ItemSelection(itemId: UUID(), entryId: nil))
                        .accentColor(.teal)
                        .tint(.teal)
                        .frame(minWidth: 600, minHeight: 400)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll( .below(NetworkModules.table.linkWindowId, fallback: WindowIdentifier.game.rawValue))
            
            WindowGroup("Map Book Viewer", id: WindowIdentifier.mapBookViewer.rawValue, for: ItemSelection.self) { $selection in
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.mapRoot.viewController.mapBookWindow(selection: selection ?? ItemSelection(itemId: UUID(), entryId: nil))
                        .accentColor(.teal)
                        .tint(.teal)
                        .frame(minWidth: 600, minHeight: 400)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll( .below(NetworkModules.table.linkWindowId, fallback: WindowIdentifier.game.rawValue))
            
            BaseWindow("Map Edit Viewer", id: WindowIdentifier.mapEditor.rawValue) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.mapRoot.viewController.mapEditWindow()
                        .accentColor(.teal)
                        .tint(.teal)
                        .frame(minWidth: 600, minHeight: 400)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll( .below(WindowIdentifier.game.rawValue))
            
            WindowGroup("Pdf Viewer", id: WindowIdentifier.pdfViewer.rawValue, for: ItemSelection.self) { $selection in
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.pdfRoot.viewController.pdfWindow(selection: selection ?? ItemSelection(itemId: UUID(), entryId: nil))
                        .accentColor(.teal)
                        .tint(.teal)
                        .frame(minWidth: 600, minHeight: 400)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll( .below(WindowIdentifier.game.rawValue))
            
            WindowGroup("Photo Viewer", id: WindowIdentifier.photoViewer.rawValue, for: ItemSelection.self) { $selection in
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.photoRoot.viewController.photoWindow(selection: selection ?? ItemSelection(itemId: UUID(), entryId: nil))
                        .accentColor(.teal)
                        .tint(.teal)
                        .frame(minWidth: 600, minHeight: 400)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll( .above(WindowIdentifier.game.rawValue))
            
            WindowGroup("Character Viewer", id: WindowIdentifier.valueViewer.rawValue, for: ItemSelection.self) { $selection in
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.valueRoot.viewController.characterWindow(selection: selection ?? ItemSelection(itemId: UUID(), entryId: nil))
                        .accentColor(.teal)
                        .tint(.teal)
                        .frame(minWidth: 600, minHeight: 400)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll( .below(NetworkModules.table.linkWindowId, fallback: WindowIdentifier.game.rawValue))
            
            WindowGroup("Table Viewer", id: WindowIdentifier.tableViewer.rawValue, for: ItemSelection.self) { $selection in
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.tableRoot.viewController.tableSheetWindow(selection: selection ?? ItemSelection(itemId: UUID(), entryId: nil))
                        .accentColor(.teal)
                        .tint(.teal)
                        .frame(minWidth: 600, minHeight: 400)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll( .below(NetworkModules.table.linkWindowId, fallback: WindowIdentifier.game.rawValue))
            
            WindowGroup("Weather Viewer", id: WindowIdentifier.weatherViewer.rawValue, for: ItemSelection.self) { $selection in
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.weatherRoot.viewController.weatherWindow(selection: selection ?? ItemSelection(itemId: UUID(), entryId: nil))
                        .accentColor(.teal)
                        .tint(.teal)
                        .frame(minWidth: 600, minHeight: 400)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll( .above(NetworkModules.table.linkWindowId, fallback: WindowIdentifier.game.rawValue))
            
        }
        .defaultSize(CGSize(width: 600, height: 800))
    }
}
#endif
