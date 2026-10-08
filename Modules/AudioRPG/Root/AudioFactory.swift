// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum AudioFactory {
    @MainActor public static func root(tagController: TagController) -> AudioRootModel {
        AudioRootModel(tagController: tagController)
    }

    @MainActor public static func rootView() -> some View {
        AudioRootView()
    }

    @MainActor @ViewBuilder public static func detailView(root: AudioRootModel) -> some View {
        if let itemId = root.navigationModel.selectedItemId {
            ItemSplitDetailRouteRootView(root: root.rootController, route: AudioRoute.detail(itemId))
        } else {
            SplitContentUnavailableView(module: root.configurable.module)
        }
    }
}
