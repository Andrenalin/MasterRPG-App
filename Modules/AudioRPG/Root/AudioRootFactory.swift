// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
public struct AudioRootFactory {
    public static func rootModel(modelContext: ModelContext) -> AudioRootModel {
        AudioRootModel(modelContext: modelContext)
    }

    public static func rootView() -> some View {
        AudioRootView()
    }
    
    @ViewBuilder
    public static func detailView(root: AudioRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
