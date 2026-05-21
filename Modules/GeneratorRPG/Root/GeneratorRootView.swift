// @copyright André Trettin


import CoreRPG
import SwiftData
import SwiftUI

struct GeneratorRootView: View {
    @Environment(GeneratorRootModel.self) private var root

    var body: some View {
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

        Color.clear
            .applyItemRootRoute(listControllable: root.folderListController, route: $route)
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
            .onChange(of: root.navigationModel.selectedItemId) {
                // Surface deep-linked selections written by `WindowRouter` (macOS Editor window's
                // direct-selection path) into the local SceneStorage route + list model.
                if let itemId = root.navigationModel.selectedItemId {
                    route <=> GeneratorRoute.detail(itemId)
                    if root.folderListController.listModel.selectedItemId != itemId {
                        root.folderListController.listModel.set(selectedItemId: itemId)
                    }
                }
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        GeneratorRootView()
    }
}
