// @copyright André Trettin

import SwiftUI

public struct ItemRootView: View {
    public init(root: ItemRootController) {
        self.root = root
    }
    
    let root: ItemRootController
    
    @Environment(\.colorScheme) private var colorScheme
    
    public var body: some View {
        let _ = Self._printChanges()
        ItemRootListView(root: root)
            .environment(root.folderListControllable.cacheListItemModel)
            .environment(root)
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
    }
}

struct ItemRootListView: View {
    let root: ItemRootController
    
    var body: some View {
        let _ = Self._printChanges()
        ListRootView(root: root, listController: root.folderListControllable, parentModel: nil)
            .searchItemList(listControllable: root.folderListControllable)
            .navigationAutoReceive(InternalRoute.self)
    }
}


public struct ItemSplitDetailRouteRootView<Route: NavigationDestination>: View {
    public init(root: ItemRootController, route: Route) {
        self.root = root
        self.route = route
    }
    
    let root: ItemRootController
    let route: Route
    
    public var body: some View {
        let _ = Self._printChanges()
        ManagedNavigationStack(name: "Split-\(root.configurable.module.token)") {
            if listModel.navigationModel.selectedItemId != nil {
                route
            } else {
                SplitContentUnavailableView(module: root.configurable.module)
            }
        }
        .environment(root)
        .tint(root.configurable.module.tint)
        .accentColor(root.configurable.module.tint)
    }
    
    var listModel: FolderListModel {
        root.folderListControllable.listModel
    }
}



struct SplitContentDetailRootView: View {
    let root: ItemRootController
    let itemId: UUID?
    
    var body: some View {
        let _ = Self._printChanges()
        if let itemId {
            root.folderListControllable.detailDestination(for: itemId).asAnyView()
        } else {
            SplitContentUnavailableView(module: root.configurable.module)
        }
    }
}
