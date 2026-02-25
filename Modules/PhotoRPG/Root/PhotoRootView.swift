// @copyright André Trettin

import CoreRPG

import SwiftUI

struct PhotoRootView: View {
    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        
        ItemRootView(root: root.rootController)
            .overlay {
                SaveView(root: root)
            }
    }
}

struct SaveView: View {
    let root: PhotoRootModel
    
    @SceneStorage("PhotoRoute") private var route: PhotoRoute?
    @SceneStorage("PhotoDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("PhotoListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {

        Color.clear
            .applyItemRootRoute(listControllable: root.folderListController, route: $route)
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        PhotoRootView()
    }
}
