// @copyright André Trettin

import CoreRPG
import SwiftUI

public enum DiceFactory {
    @MainActor public static func root(tagController: TagController) -> DiceRootModel {
        DiceRootModel(tagController: tagController)
    }

    @MainActor public static func rootView() -> some View {
        DiceRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: DiceRootModel) -> some View {
        if let itemId = root.navigationModel.selectedItemId {
            ManagedNavigationStack(name: "Split-Dice") {
                ItemSplitDetailRouteRootView(root: root.rootController, route: DiceRoute.detail(itemId))
            }
        } else {
            SplitContentUnavailableView(module: root.configurable.module)
        }
    }
}
