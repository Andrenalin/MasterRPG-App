// @copyright André Trettin

import CoreRPG

import SwiftUI

struct TableRootView: View {
    @Environment(TableRootModel.self) private var root

    var body: some View {
        
        ItemRootView(root: root.rootController)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: TableRootModel
    
    @SceneStorage("TableRoute") private var route: TableRoute?
    @SceneStorage("TableDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("TableListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {

        Color.clear
            .applyItemRootRoute(listControllable: root.folderListController, route: $route)
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        TableRootView()
    }
}
