// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import SwiftData
import SwiftUI

public enum TableFactory {
    @MainActor public static func root(tagController: TagController, diceRoot: DiceRootModel, pdfRoot: PdfRootModel) -> TableRootModel {
        TableRootModel(tagController: tagController, diceRoot: diceRoot, pdfRoot: pdfRoot)
    }

    @MainActor public static func rootView() -> some View {
        TableRootView()
    }

    @MainActor @ViewBuilder public static func detailView(root: TableRootModel) -> some View {
        let selectedItemId = root.navigationModel.selectedItemId

        if let itemId = selectedItemId {
            ItemSplitDetailRouteRootView(root: root.rootController, route: TableRoute.detail(itemId))
        }
    }
}
