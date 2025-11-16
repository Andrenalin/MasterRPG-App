// @copyright André Trettin

import AndrenalinKit
import SwiftData
import SwiftUI

public enum SpaceFactory {
    @MainActor public static func root(container: ModelContainer) -> SpaceRootModel {
        SpaceRootModel(container: container)
    }
    
    public static func rootView() -> some View {
        SpaceRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: SpaceRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
