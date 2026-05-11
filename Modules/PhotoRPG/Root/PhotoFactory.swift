// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum PhotoFactory {
    @MainActor public static func root(tagController: TagController) -> PhotoRootModel {
        PhotoRootModel(tagController: tagController)
    }

    @MainActor public static func rootView() -> some View {
        PhotoRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: PhotoRootModel) -> some View {
        let selectedItemId = root.navigationModel.selectedItemId

        if let itemId = selectedItemId {
            ItemSplitDetailRouteRootView(root: root.rootController, route: PhotoRoute.detail(itemId))
        }
    }
}
