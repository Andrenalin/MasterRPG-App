// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PhotoRootView: View {
    @Environment(PhotoRootModel.self) private var root
    @Environment(\.navigator) private var navigator

    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                StateRestorationView(root: root)
            }
            .onNavigationReceive { (route: PhotoRoute, navigator) in
                // Handle deep links from send() calls
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

struct StateRestorationView: View {
    let root: PhotoRootModel

    @SceneStorage("PhotoSelectedItem") private var selectedItemId: String?
    @SceneStorage("PhotoDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("PhotoListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        Color.clear
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
            .onChange(of: root.navigationModel.selectedItemId) {
                // Sync AppNavigationModel -> SceneStorage
                if let itemId = root.navigationModel.selectedItemId {
                    selectedItemId = itemId.uuidString
                } else {
                    selectedItemId = nil
                }

                // Sync AppNavigationModel -> FolderListModel
                if let itemId = root.navigationModel.selectedItemId {
                    if root.folderListController.listModel.selectedItemId != itemId {
                        root.folderListController.listModel.set(selectedItemId: itemId)
                    }
                } else {
                    if root.folderListController.listModel.selected != nil {
                        root.folderListController.listModel.update(selection: Set())
                    }
                }
            }
            .onChange(of: root.folderListController.listModel.selectedItemId) {
                // Sync FolderListModel -> AppNavigationModel
                let listSelectedId = root.folderListController.listModel.selectedItemId
                if root.navigationModel.selectedItemId != listSelectedId {
                    root.navigationModel.selectedItemId = listSelectedId
                }
            }
            .onChange(of: selectedItemId, initial: true) {
                // Restore from SceneStorage on app launch/scene restoration
                Task {
                    // Small delay to allow model initialization
                    try? await Task.sleep(for: .milliseconds(100))

                    if let itemIdString = selectedItemId, let itemId = UUID(uuidString: itemIdString) {
                        if root.navigationModel.selectedItemId != itemId {
                            root.navigationModel.selectedItemId = itemId
                        }
                    } else if selectedItemId == nil && root.navigationModel.selectedItemId != nil {
                        root.navigationModel.selectedItemId = nil
                    }
                }
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        PhotoRootView()
    }
}
