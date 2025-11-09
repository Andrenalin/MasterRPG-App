// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftData
import SwiftUI

public enum AudioFactory {
    @MainActor
    public static func root(container: ModelContainer) -> AudioRoot {
        AudioRoot(container: container)
    }

    @MainActor
    public static func rootView() -> some View {
        AudioRootView()
    }

    @MainActor @ViewBuilder public static func detailView(root: AudioRoot) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
