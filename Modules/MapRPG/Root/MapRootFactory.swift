// @copyright André Trettin

import CharacterRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG

import SwiftData
import SwiftUI

@MainActor
public struct MapRootFactory {
    public static func rootModel(modelContext: ModelContext, characterRoot: CharacterRootModel, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) -> MapRootModel {
        MapRootModel(modelContext: modelContext, characterRoot: characterRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }

    public static func rootView(withoutNavigation: Bool) -> some View {
        MapRootView(withoutNavigation: withoutNavigation)
    }
}
