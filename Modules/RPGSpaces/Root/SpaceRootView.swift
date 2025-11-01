// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

struct SpaceRootView: View {
    let isTabbed: Bool
    
    @Environment(SpaceRoot.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        if isTabbed {
            //ManagedNavigationStack(name: "Space") { _ in
                pureContent
            //}
            .environment(root.rootController)
            .navigationAutoReceive(SpaceNewRoute.self)
        } else {
            splitWithDetail()
        }
    }
    
    var pureContent: some View {
        ItemRootView(root: root.rootController)
            .navigationAutoReceive(SpaceRoute.self)
            .overlay {
                SaveView(root: root)
            }
    }
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    func contentView() -> some View {
        ManagedPresentationView {
            pureContent
        }
        .environment(root.rootController)
    }
    
    func splitWithDetail() -> some View {
        NavigationSplitView(columnVisibility: $column, preferredCompactColumn: $preferredCompactColumn) {
            contentView()
        } detail: {
            ItemSplitDetailRootView(root: root.rootController)
        }
    }
}

struct SaveView: View {
    let root: SpaceRoot
    
    @SceneStorage("SpaceRoute") private var route: SpaceNewRoute?
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
        SpaceRootView(isTabbed: false)
    }
}
