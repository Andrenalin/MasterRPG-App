// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import SwiftData
import SwiftUI

@MainActor
public struct TableRootFactory {
    public static func rootModel(modelContext: ModelContext, diceRoot: DiceRootModel, pdfRoot: PdfRootModel) -> TableRootModel {
        TableRootModel(modelContext: modelContext, diceRoot: diceRoot, pdfRoot: pdfRoot)
    }

    public static func rootView() -> some View {
        TableRootView()
    }
    
    @ViewBuilder
    public static func detailView(root: TableRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
