// @copyright André Trettin

import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
public struct CharacterRootFactory {
    public static func rootModel(modelContext: ModelContext, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) -> CharacterRootModel {
        CharacterRootModel(modelContext: modelContext, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }

    public static func rootView() -> some View {
        CharacterRootView()
    }
    
    @ViewBuilder
    public static func detailView(root: CharacterRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
