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
        // The split's only detail stack. The module factories wrapped this view in a second
        // `ManagedNavigationStack`; a stack nested in another stack's root is not supported.
        ManagedNavigationStack(name: "Split-\(root.configurable.module.token)") {
            Group {
                if listModel.navigationModel.selectedItemId != nil {
                    route
                } else {
                    SplitContentUnavailableView(module: root.configurable.module)
                }
            }
            .splitDetailPopsToRoot(onSelectionChangeIn: listModel.navigationModel)
        }
        .environment(root)
        .moduleTint(root.configurable.module)
    }

    var listModel: FolderListModel {
        root.folderListControllable.listModel
    }
}

private extension View {
    /// Pops the split's detail stack back to its root when the list column selects another
    /// item. The root is replaced with the new selection either way; without the pop it
    /// changed underneath a folder member that was still pushed on top.
    func splitDetailPopsToRoot(onSelectionChangeIn navigationModel: ModuleNavigationModel) -> some View {
        modifier(SplitDetailPopToRootModifier(navigationModel: navigationModel))
    }
}

private struct SplitDetailPopToRootModifier: ViewModifier {
    let navigationModel: ModuleNavigationModel

    @Environment(\.navigator) private var navigator

    func body(content: Content) -> some View {
        content
            .onChange(of: navigationModel.selectedItemId) {
                navigator.popAll()
            }
    }
}

#Preview("Split Detail") {
    ItemSplitDetailRouteRootView(root: ItemRootController.fake, route: InternalRoute.removeAlert)
}
