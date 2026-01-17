// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

public enum SpaceFactory {
    @MainActor public static func root(tagController: TagController) -> SpaceRootModel {
        SpaceRootModel(tagController: tagController)
    }
    
    public static func rootView() -> some View {
        SpaceRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: SpaceRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
