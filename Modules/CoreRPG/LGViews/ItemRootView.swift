// @copyright André Trettin

import SwiftUI

public struct ItemRootView: View {
    public init(root: ItemRootController) {
        self.root = root
    }
    
    let root: ItemRootController
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        ItemRootListView(root: root)
            .environment(root)
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
            .task {
                root.navigationModel.navigator = navigator
            }
    }
}

struct ItemRootListView: View {
    let root: ItemRootController
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
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
        let _ = Self.printViewChangesOnlyInDebug()
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
