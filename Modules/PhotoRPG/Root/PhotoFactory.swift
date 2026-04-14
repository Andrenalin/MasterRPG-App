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
    
    @MainActor public static func detailView(root: PhotoRootModel) -> some View {
        ItemSplitDetailRouteRootView(root: root.rootController, route: PhotoRoute.detail(root.navigationModel.selectedItemId ?? UUID()))
    }
}
