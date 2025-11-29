// @copyright André Trettin

import CoreRPG

import SwiftUI

struct SpaceRootView: View {
    @Environment(SpaceRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        ItemRootView(root: root.rootController)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: SpaceRootModel
    
    @SceneStorage("SpaceRoute") private var route: SpaceRoute?
    @SceneStorage("SpaceDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("SpaceListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.folderListController, route: $route)
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        SpaceRootView()
    }
}
