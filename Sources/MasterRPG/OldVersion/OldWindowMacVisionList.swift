// @copyright André Trettin

#if os(visionOS) || os(macOS)
import AndrenalinKit
import RoleGameKit
import SwiftUI
import RPGAdventures
import MapRPG
import MapRPG
import PdfRPG
import PhotoRPG
import CharacterRPG
import PhotoRPG
import WeatherRPG
import TableRPG

struct OldWindowMacVisionList: Scene {
    let appModel: AppModel
    
    var body: some Scene {
        Group {            
            WindowGroup("Map Book Viewer", id: WindowIdentifier.mapBookViewer.rawValue, for: ItemSelection.self) { $selection in
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.mapRoot.viewController.mapBookWindow(root: appModel.mapRoot, selection: selection ?? ItemSelection(itemId: UUID(), entryId: nil))
                        .accentColor(.teal)
                        .tint(.teal)
                        .frame(minWidth: 600, minHeight: 400)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll( .below(NetworkModules.table.linkWindowId, fallback: WindowIdentifier.game.rawValue))
            
            BaseWindow("Map Edit Viewer", id: WindowIdentifier.mapEditor.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.mapRoot.viewController.mapEditWindow(root: appModel.mapRoot)
                        .accentColor(.teal)
                        .tint(.teal)
                        .frame(minWidth: 600, minHeight: 400)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll( .below(WindowIdentifier.game.rawValue))                        
        }
        .defaultSize(CGSize(width: 600, height: 800))
    }
}
#endif
