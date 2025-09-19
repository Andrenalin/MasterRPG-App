// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct AdventureRootView: View {
    let withoutNavigation: Bool

    @Environment(AdventureRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController, withoutNavigation: withoutNavigation) {
            DetailRootView(selectedId: nil)
        }
        .overlay {
            SaveView(root: root)
        }
        .navigationAutoReceive(AdventureRoute.self)
    }
}

struct SaveView: View {
    let root: AdventureRootModel
    
    @SceneStorage("AdventureRoute") private var route: ItemRootRoute?
    @SceneStorage("AdventureDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("AdventureListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview("Embed", traits: .mockData) {
    ManagedNavigationStack {
        AdventureRootView(withoutNavigation: true)
    }
}

#Preview("Split", traits: .mockData) {
    AdventureRootView(withoutNavigation: false)
}

