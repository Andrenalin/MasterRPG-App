// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct AdventureRootView: View {
    @Environment(AdventureRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController)
            .navigationAutoReceive(AdventureRoute.self)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: AdventureRootModel
    
    @SceneStorage("AdventureRoute") private var route: ItemRootRoute?
    @SceneStorage("AdventureDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("AdventureListModel") private var listMode: ListDisplayModel.ListMode = .list

    @Environment(\.navigator) private var navigator
    
    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        AdventureRootView()
    }
}
