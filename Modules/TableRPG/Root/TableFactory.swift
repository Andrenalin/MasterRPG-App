// @copyright André Trettin

import CoreRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import PdfRPG
import SwiftUI

public enum TableFactory {
    @MainActor public static func root(tagController: TagController, diceRoot: DiceRootModel, generatorRoot: GeneratorRootModel? = nil, pdfRoot: PdfRootModel) -> TableRootModel {
        TableRootModel(tagController: tagController, diceRoot: diceRoot, generatorRoot: generatorRoot, pdfRoot: pdfRoot)
    }

    @MainActor public static func rootView() -> some View {
        TableRootView()
    }

    @MainActor @ViewBuilder public static func detailView(root: TableRootModel) -> some View {
        if let itemId = root.navigationModel.selectedItemId {
            ItemSplitDetailRouteRootView(root: root.rootController, route: TableRoute.detail(itemId))
        } else {
            SplitContentUnavailableView(module: root.configurable.module)
        }
    }
}
