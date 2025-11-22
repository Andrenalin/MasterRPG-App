// @copyright André Trettin

import AndrenalinKit
import SwiftData
import SwiftUI

@MainActor
public struct GeneratorRootFactory {
    public static func rootModel(container: ModelContainer) -> GeneratorRootModel {
        GeneratorRootModel(container: container)
    }
    
    public static func rootView() -> some View {
        GeneratorRootView()
    }
    
    @ViewBuilder public static func detailView(root: GeneratorRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
