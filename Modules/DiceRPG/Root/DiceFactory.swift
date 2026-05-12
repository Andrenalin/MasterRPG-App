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
    
    public static func diceImage(for die: RawDie, result: Int) -> Image {
        let model = DieModel(id: UUID(), die: die)
        return model.diceImage(for: result)
    }
    
    @MainActor @ViewBuilder public static func detailView(root: DiceRootModel, selectedItemId: UUID?) -> some View {
        if let itemId = selectedItemId {
            ItemSplitDetailRouteRootView(root: root.rootController, route: DiceRoute.detail(itemId))
        }
    }
}
