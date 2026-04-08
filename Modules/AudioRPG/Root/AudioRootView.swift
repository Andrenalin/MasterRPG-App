// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AudioRootView: View {
    @Environment(AudioRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                StateRestorationView(root: root)
            }
            .onNavigationReceive { (route: AudioRoute, navigator) in
                // Handle deep links from send() calls
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

struct StateRestorationView: View {
    let root: AudioRootModel

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @SceneStorage("AudioSelectedItem") private var selectedItemId: String?
    @SceneStorage("AudioDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("AudioListModel") private var listMode: ListDisplayModel.ListMode = .list

    @State private var route: AudioRoute?

    var body: some View {
        Color.clear
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
            .applyIf(appSizeModel.mode == .compact) {
                $0.navigate(to: $route)
                    .onChange(of: route) {
                        // Detect back navigation: when photoRoute becomes nil, user navigated back
                        if route == nil && root.navigationModel.selectedItemId != nil {
                            // Clear selection when back navigation happened
                            root.navigationModel.selectedItemId = nil
                        }
                    }
            }
            .onChange(of: root.navigationModel.selectedItemId) {
                // Sync AppNavigationModel -> SceneStorage and photoRoute
                if let itemId = root.navigationModel.selectedItemId {
                    route <=> AudioRoute.detail(itemId)

                    selectedItemId <=> itemId.uuidString
                    if root.folderListController.listModel.selectedItemId != itemId {
                        root.folderListController.listModel.set(selectedItemId: itemId)
                    }
                } else {
                    route <=> nil
                    selectedItemId <=> nil
                    if root.folderListController.listModel.selected != nil {
                        root.folderListController.listModel.update(selection: Set())
                    }
                }
            }
            .onAppear() {
                // Restore from SceneStorage on app launch/scene restoration
                Task {
                    // Small delay to allow model initialization
                    try? await Task.sleep(for: .milliseconds(100))

                    if let itemIdString = selectedItemId, let itemId = UUID(uuidString: itemIdString) {
                        if root.navigationModel.selectedItemId != itemId {
                            root.navigationModel.selectedItemId = itemId
                        }
                    } else {
                        selectedItemId <=> nil
                        root.navigationModel.selectedItemId <=> nil
                    }
                }
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        AudioRootView()
    }
}
