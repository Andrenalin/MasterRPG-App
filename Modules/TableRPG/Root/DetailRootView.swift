// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import SwiftData
import SwiftUI
import CoreExternalRPG

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator
    
    @Environment(LinkRootController.self) private var linkController
    @Environment(TableRootModel.self) private var root
    
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.table.viewerkWindowId, canShow: true, route: { DetailRoute.viewer($0) })
    @State private var tableSheetModel: TableSheetModel?
    @State private var showQuickEditor: Bool = false
    
    var body: some View {
        CoreRPG.DetailRootView(selectedId: selectedId) {
        } editor: {
            if let tableModel {
                detailEditorView(model: tableModel)
            }
        } inspector: {
            LinkRootView(type: .inspector)
        }
        .navigationDestination(for: SelectionDiceRoute.self) { route in
            route
                .environment(root.editController.selectionDice)
        }
        .navigationDestination(for: SelectionPdfRoute.self) { route in
            route
                .environment(root.editController.selectionPdf)
        }
        .navigationDestination(for: TableEditorRoute.self) { route in
            route
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.inlineViewer(root: root, with: openFileWindowModel.itemId) {
                    openFileWindowModel.showItem = false
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigator.navigate(to: TableEditorRoute.quickEditor, method: .managedCover)
                } label: {
                    Image(systemName: "table.badge.more")
                }
            }
        }
        .environment(openFileWindowModel)
    }
    
    var selectedModel: ItemDataModel? {
        root.listControllable.selectedModel(for: selectedId, modelContext: modelContext)
    }

    var tableModel: TableDataModel? {
        root.itemController.model(for: selectedId ?? root.listControllable.listModel.selectedItemId)
    }

    @ViewBuilder
    func detailEditorView(model: TableDataModel) -> some View {
        root.diceRoot.viewController.selectionView(root: root.diceRoot, model: root.editController.selectionDice)
            .onChange(of: root.editController.selectionDice.selection) {
                withAnimation { root.editController.add(diceId: root.editController.selectionDice.itemId, model: model) }
            }
            .onChange(of: model.diceId, initial: true) {
                withAnimation { root.editController.selectionDice.resetSelection(itemId: model.diceId) }
            }

        EntryList(itemId: model.itemId)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [ItemDataModel]
    @Previewable @Environment(TableRootModel.self) var root
    
    NavigationStack {
        DetailRootView(selectedId: MockData.previewId)
    }
    .onAppear {
        root.listControllable.update(items: models, parentModel: nil)
        root.listControllable.listModel.set(selectedItemId: models.first!.id)
    }
}
