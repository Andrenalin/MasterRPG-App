// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct GeneratorRootView: View {
    @Environment(GeneratorRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController)
            .navigationAutoReceive(GeneratorRoute.self)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: GeneratorRootModel
    
    @SceneStorage("GeneratorRoute") private var route: ItemRootRoute?
    @SceneStorage("GeneratorDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("GeneratorListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        GeneratorRootView()
    }
}
