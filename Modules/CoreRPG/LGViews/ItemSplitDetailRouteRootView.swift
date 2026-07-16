// @copyright André Trettin

import SwiftUI

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

#Preview("Split Detail") {
    ItemSplitDetailRouteRootView(root: ItemRootController.fake, route: InternalRoute.removeAlert)
}
