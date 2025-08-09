// @copyright André Trettin

import SwiftData
import SwiftUI

@MainActor
public struct DiceRootFactory {
    public static func rootModel(modelContext: ModelContext) -> DiceRootModel {
        DiceRootModel(modelContext: modelContext)
    }

    public static func rootView(withoutNavigation: Bool) -> some View {
        DiceRootView(withoutNavigation: withoutNavigation)
        
    }
}
