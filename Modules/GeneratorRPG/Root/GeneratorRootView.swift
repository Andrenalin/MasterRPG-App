// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftData
import SwiftUI

struct GeneratorRootView: View {
    @Environment(GeneratorRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        ItemRootView(root: root.rootController)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: GeneratorRootModel
    
    @SceneStorage("GeneratorRoute") private var route: GeneratorRoute?
    @SceneStorage("GeneratorDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .regular
    @SceneStorage("GeneratorListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.folderListController, route: $route)
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        GeneratorRootView()
    }
}
