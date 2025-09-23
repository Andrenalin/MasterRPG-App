// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct MapRootView: View {
    let withoutNavigation: Bool

    @Environment(MapRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController, withoutNavigation: withoutNavigation)
            .navigationAutoReceive(MapRoute.self)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: MapRootModel
    
    @SceneStorage("MapRoute") private var route: ItemRootRoute?
    @SceneStorage("MapDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("MapListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview("Embed", traits: .mockData) {
    ManagedNavigationStack {
        MapRootView(withoutNavigation: true)
    }
}

#Preview("Split", traits: .mockData) {
    MapRootView(withoutNavigation: false)
}

