// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
public struct PdfRootFactory {
    public static func rootModel(modelContext: ModelContext) -> PdfRootModel {
        PdfRootModel(modelContext: modelContext)
    }
    
    public static func rootView() -> some View {
        PdfRootView()
    }
    
    @ViewBuilder
    public static func detailView(root: PdfRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
