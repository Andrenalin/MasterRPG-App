// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
public struct DiceRootFactory {
    public static func rootModel(modelContext: ModelContext) -> DiceRootModel {
        DiceRootModel(modelContext: modelContext)
    }

    public static func rootView() -> some View {
        DiceRootView()
    }
    
    @ViewBuilder
    public static func detailView(root: DiceRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
