// @copyright André Trettin


import CoreRPG
import SwiftUI

public enum PdfFactory {
    @MainActor public static func root(tagController: TagController) -> PdfRootModel {
        PdfRootModel(tagController: tagController)
    }
    
    @MainActor public static func rootView() -> some View {
        PdfRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: PdfRootModel) -> some View {
        if let itemId = root.navigationModel.selectedItemId {
            ManagedNavigationStack(name: "Split-Pdf") {
                ItemSplitDetailRouteRootView(root: root.rootController, route: PdfRoute.detail(itemId))
            }
        } else {
            SplitContentUnavailableView(module: root.configurable.module)
        }
    }
}
