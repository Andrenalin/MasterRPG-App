// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftData
import SwiftUI

public enum PdfFactory {
    @MainActor public static func root(container: ModelContainer) -> PdfRoot {
        PdfRoot(container: container)
    }
    
    public static func rootView() -> some View {
        PdfRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: PdfRoot) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
