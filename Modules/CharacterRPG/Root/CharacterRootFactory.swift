// @copyright André Trettin

import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG

import SwiftData
import SwiftUI

@MainActor
public struct CharacterRootFactory {
    public static func rootModel(modelContext: ModelContext, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) -> CharacterRootModel {
        CharacterRootModel(modelContext: modelContext, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }

    public static func rootView(withoutNavigation: Bool) -> some View {
        CharacterRootView(withoutNavigation: withoutNavigation)
    }
}
