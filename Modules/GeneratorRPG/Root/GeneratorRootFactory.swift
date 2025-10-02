// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
public struct GeneratorRootFactory {
    public static func rootModel(modelContext: ModelContext) -> GeneratorRootModel {
        GeneratorRootModel(modelContext: modelContext)
    }

    public static func rootView() -> some View {
        GeneratorRootView()
    }
    
    @ViewBuilder
    public static func detailView(root: GeneratorRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
