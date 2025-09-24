// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
public struct PhotoRootFactory {
    public static func rootModel(modelContext: ModelContext) -> PhotoRootModel {
        PhotoRootModel(modelContext: modelContext)
    }

    public static func rootView() -> some View {
        PhotoRootView()
    }
    
    @ViewBuilder
    public static func detailView(root: PhotoRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
