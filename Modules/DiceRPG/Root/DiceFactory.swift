// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

public enum DiceFactory {
    @MainActor public static func root(container: ModelContainer) -> DiceRootModel {
        DiceRootModel(container: container)
    }

    @MainActor public static func rootView() -> some View {
        DiceRootView()
    }
    
    public static func diceImage(for die: RawDie, result: Int) -> Image {
        let model = DieModel(id: UUID(), die: die)
        return model.diceImage(for: result)
    }
    
    @MainActor @ViewBuilder public static func detailView(root: DiceRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
