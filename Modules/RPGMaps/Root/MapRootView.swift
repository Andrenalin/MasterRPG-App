// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftUI

struct MapRootView: View {
    @Environment(MapRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController)
            .navigationAutoReceive(MapRoute.self)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: MapRootModel
    
    @SceneStorage("MapRoute") private var route: MapRoute?
    @SceneStorage("MapDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("MapListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.folderListController, route: $route)
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        MapRootView()
    }
}
