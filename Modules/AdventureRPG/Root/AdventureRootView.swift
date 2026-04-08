// @copyright André Trettin

import CoreRPG

import SwiftUI

struct AdventureRootView: View {
    @Environment(AdventureRootModel.self) private var root
    @Environment(\.navigator) private var navigator

    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                StateRestorationView(root: root)
            }
            .onNavigationReceive { (route: AdventureRoute, navigator) in
                // Handle deep links from send() calls
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

struct StateRestorationView: View {
    let root: AdventureRootModel

    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @SceneStorage("AdventureSelectedItem") private var selectedItemId: String?
    @SceneStorage("AdventureDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("AdventureListModel") private var listMode: ListDisplayModel.ListMode = .list

    @State private var route: AdventureRoute?

    var body: some View {
        Color.clear
            .syncListDisplay(listControllable: root.folderListController, displayMode: $displayMode, listMode: $listMode)
            .applyIf(appSizeModel.mode == .compact) {
                $0.navigate(to: $route)
                    .onChange(of: route) {
                        // Detect back navigation: when route becomes nil, user navigated back
                        if route == nil && root.navigationModel.selectedItemId != nil {
                            // Clear selection when back navigation happened
                            root.navigationModel.selectedItemId = nil
                        }
                    }
            }
            .onChange(of: root.navigationModel.selectedItemId) {
                // Sync AppNavigationModel -> SceneStorage and route
                if let itemId = root.navigationModel.selectedItemId {
                    route <=> AdventureRoute.detail(itemId)

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
        AdventureRootView()
    }
}
