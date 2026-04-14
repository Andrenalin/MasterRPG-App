// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import SwiftData
import SwiftUI

public enum CharacterRootFactory {
    @MainActor public static func root(tagController: TagController, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) -> CharacterRootModel {
        CharacterRootModel(tagController: tagController, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }
    
    @MainActor public static func rootView() -> some View {
        CharacterRootView()
    }
    
    @MainActor public static func detailView(root: CharacterRootModel) -> some View {
        ItemSplitDetailRouteRootView(root: root.rootController, route: CharacterRoute.detail(root.navigationModel.selectedItemId ?? UUID()))

    }
}
