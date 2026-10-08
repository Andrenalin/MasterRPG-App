// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum RuleFactory {
    @MainActor
    public static func root(tagController: TagController) -> RuleRootModel {
        RuleRootModel(tagController: tagController)
    }

    @MainActor
    public static func rootView() -> some View {
        RuleRootView()
    }

    @MainActor @ViewBuilder
    public static func detailView(root: RuleRootModel) -> some View {
        if let itemId = root.navigationModel.selectedItemId {
            ItemSplitDetailRouteRootView(
                root: root.rootController,
                route: RuleRoute.detail(itemId)
            )
        } else {
            SplitContentUnavailableView(module: .rule)
        }
    }
}

