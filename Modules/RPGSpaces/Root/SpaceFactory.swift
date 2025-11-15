// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftData
import SwiftUI

public enum SpaceFactory {
    @MainActor public static func root(container: ModelContainer) -> SpaceRoot {
        SpaceRoot(container: container)
    }
    
    public static func rootView() -> some View {
        SpaceRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: SpaceRoot) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
