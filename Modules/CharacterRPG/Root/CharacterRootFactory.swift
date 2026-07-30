// @copyright André Trettin

import CoreRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import PdfRPG
import PhotoRPG
import TableRPG
import SwiftData
import SwiftUI

public enum CharacterRootFactory {
    @MainActor public static func root(tagController: TagController, diceRoot: DiceRootModel, generatorRoot: GeneratorRootModel? = nil, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) -> CharacterRootModel {
        CharacterRootModel(tagController: tagController, diceRoot: diceRoot, generatorRoot: generatorRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }
    
    @MainActor public static func rootView() -> some View {
        CharacterRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: CharacterRootModel) -> some View {
        if let itemId = root.navigationModel.selectedItemId {
            ManagedNavigationStack(name: "Split-Character") {
                ItemSplitDetailRouteRootView(root: root.rootController, route: CharacterRoute.detail(itemId))
            }
        } else {
            SplitContentUnavailableView(module: root.configurable.module)
        }
    }
}
