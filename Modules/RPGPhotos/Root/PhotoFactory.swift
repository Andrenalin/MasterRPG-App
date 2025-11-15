// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import SwiftData
import SwiftUI

public enum PhotoFactory {
    @MainActor
    public static func root(container: ModelContainer) -> PhotoRoot {
        PhotoRoot(container: container)
    }

    @MainActor
    public static func rootView() -> some View {
        PhotoRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: PhotoRoot) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
