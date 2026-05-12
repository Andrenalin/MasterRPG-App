// @copyright André Trettin


import CoreRPG
import SwiftData
import SwiftUI

public enum PdfFactory {
    @MainActor public static func root(tagController: TagController) -> PdfRootModel {
        PdfRootModel(tagController: tagController)
    }
    
    public static func rootView() -> some View {
        PdfRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: PdfRootModel, selectedItemId: UUID?) -> some View {
        if let itemId = selectedItemId {
            ItemSplitDetailRouteRootView(root: root.rootController, route: PdfRoute.detail(itemId))
        }
    }
}
