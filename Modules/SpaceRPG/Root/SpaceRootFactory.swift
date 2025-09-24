// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
public struct SpaceRootFactory {
    public static func rootModel(modelContext: ModelContext) -> SpaceRootModel {
        SpaceRootModel(modelContext: modelContext)
    }

    public static func rootView() -> some View {
        SpaceRootView()
    }
    
    @ViewBuilder
    public static func detailView(root: SpaceRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
