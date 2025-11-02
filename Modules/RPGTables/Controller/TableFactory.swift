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
            .navigationAutoReceive(TableRoute.self)
    }

    @MainActor @ViewBuilder public static func detailView(root: TableRoot) -> some View {
        ExternalDetailView()
    }
}

struct ExternalDetailView: View {
    @Environment(TableRoot.self) private var root
    
    var body: some View {
        if let itemId = root.listController(tabId: KnownRoutes.mainTabId).model.selectedItem?.model.itemId {
            TableRoute.detail(itemId)
                .environment(root.listController(tabId: KnownRoutes.mainTabId).model)
        } else {
            SplitContentUnavailable(module: .table)
        }
    }
}

