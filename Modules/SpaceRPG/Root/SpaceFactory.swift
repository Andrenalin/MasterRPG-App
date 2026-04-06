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
        ItemSplitDetailRouteRootView(root: root.rootController, route: SpaceRoute.detail(root.navigationModel.selectedItemId ?? UUID()))
    }
}
