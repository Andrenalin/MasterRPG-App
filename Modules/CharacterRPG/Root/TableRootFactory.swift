// @copyright André Trettin

import DiceRPG
import SwiftData
import SwiftUI

@MainActor
public struct TableRootFactory {
    public static func rootModel(modelContext: ModelContext, diceRoot: DiceRootModel) -> CharacterRootModel {
        CharacterRootModel(modelContext: modelContext, diceRoot: diceRoot)
    }

    public static func rootView(withoutNavigation: Bool) -> some View {
        TableRootView(withoutNavigation: withoutNavigation)
    }
}
