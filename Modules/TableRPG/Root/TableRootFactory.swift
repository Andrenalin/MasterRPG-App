// @copyright André Trettin

import DiceRPG
import PdfRPG
import SwiftData
import SwiftUI

@MainActor
public struct TableRootFactory {
    public static func rootModel(modelContext: ModelContext, diceRoot: DiceRootModel, pdfRoot: PdfRootModel) -> TableRootModel {
        TableRootModel(modelContext: modelContext, diceRoot: diceRoot, pdfRoot: pdfRoot)
    }

    public static func rootView(withoutNavigation: Bool) -> some View {
        TableRootView(withoutNavigation: withoutNavigation)
    }
}
