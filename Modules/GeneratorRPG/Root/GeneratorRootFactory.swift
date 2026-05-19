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
    
    @ViewBuilder public static func detailView(root: GeneratorRootModel) -> some View {
        if let itemId = root.navigationModel.selectedItemId {
            ManagedNavigationStack(name: "Split-Generator") {
                ItemSplitDetailRouteRootView(root: root.rootController, route: GeneratorRoute.detail(itemId))
            }
        } else {
            SplitContentUnavailableView(module: root.configurable.module)
        }
    }
}
