// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import SwiftData
import SwiftUI

public enum CharacterRootFactory {
    @MainActor public static func root(container: ModelContainer, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) -> CharacterRootModel {
        CharacterRootModel(container: container, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }
    
    @MainActor public static func rootView() -> some View {
        CharacterRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: CharacterRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
