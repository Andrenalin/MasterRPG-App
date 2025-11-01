// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGDie
import RPGPdfs
import SwiftData
import SwiftUI

public enum TableFactory {
    @MainActor
    public static func root(container: ModelContainer, diceRoot: DiceRoot, pdfRoot: PdfRoot) -> TableRoot {
        TableRoot(container: container, diceRoot: diceRoot, pdfRoot: pdfRoot)
    }

    @MainActor
    public static func rootView(for root: TableRoot, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }

    @MainActor
    public static func rootExtendedView(for root: TableRoot, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
            .navigationDestinationAutoReceive(InternalRoute.self)
    }
}
