// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum SpaceFactory {
    @MainActor public static func root(tagController: TagController) -> SpaceRootModel {
        SpaceRootModel(tagController: tagController)
    }
    
    public static func rootView() -> some View {
        SpaceRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: SpaceRootModel) -> some View {
        if let itemId = root.navigationModel.selectedItemId {
            ManagedNavigationStack(name: "Split-Space") {
                ItemSplitDetailRouteRootView(root: root.rootController, route: SpaceRoute.detail(itemId))
            }
        } else {
            SplitContentUnavailableView(module: root.configurable.module)
        }
    }
}
