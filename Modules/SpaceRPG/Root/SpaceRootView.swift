// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct SpaceRootView: View {
    let withoutNavigation: Bool

    @Environment(SpaceRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController, withoutNavigation: withoutNavigation)
            .navigationAutoReceive(SpaceRoute.self)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: SpaceRootModel
    
    @SceneStorage("SpaceRoute") private var route: ItemRootRoute?
    @SceneStorage("SpaceDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("SpaceListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview("Embed", traits: .mockData) {
    ManagedNavigationStack {
        SpaceRootView(withoutNavigation: true)
    }
}

#Preview("Split", traits: .mockData) {
    SpaceRootView(withoutNavigation: false)
}

