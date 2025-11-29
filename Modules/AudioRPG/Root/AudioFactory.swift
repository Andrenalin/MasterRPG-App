// @copyright André Trettin

import CoreRPG
import CoreExternalRPG
import SwiftData
import SwiftUI

public enum AudioFactory {
    @MainActor public static func root(container: ModelContainer) -> AudioRootModel {
        AudioRootModel(container: container)
    }

    @MainActor public static func rootView() -> some View {
        AudioRootView()
    }

    @MainActor @ViewBuilder public static func detailView(root: AudioRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
