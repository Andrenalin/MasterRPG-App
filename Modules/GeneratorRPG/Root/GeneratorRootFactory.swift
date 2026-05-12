// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
public struct GeneratorRootFactory {
    public static func rootModel(tagController: TagController) -> GeneratorRootModel {
        GeneratorRootModel(tagController: tagController)
    }
    
    public static func rootView() -> some View {
        GeneratorRootView()
    }
    
    @ViewBuilder public static func detailView(root: GeneratorRootModel, selectedItemId: UUID?) -> some View {
        if let itemId = selectedItemId {
            ItemSplitDetailRouteRootView(root: root.rootController, route: GeneratorRoute.detail(itemId))
        }
    }
}
