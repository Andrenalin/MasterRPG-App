// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator
    
    @Environment(TableRootModel.self) private var root
    
    @State private var tableSheetModel: TableSheetModel?
    
    var body: some View {
        CoreRPG.DetailRootView(selectedId: selectedId) {
        } editor: {
            if let selectedModel {
                if let tableModel {
                    if !selectedModel.specialCategory {
                        // OpenFileWindowView(model: openFileWindowModel, module: root.module, windowId: WindowIdentifier.pdfViewer.rawValue, route: DetailRoute.viewer(selection.selectedItem ?? model.id))
                    }
                    detailEditorView(model: tableModel)
                }
            }
        } inspector: {
            root.diceRoot.viewController.linkWindow(root: root.diceRoot, isInspector: true)
        }
        .navigationDestination(for: SelectionDiceRoute.self) { route in
            route
                .environment(root.editController.selectionDice)
        }
        .onChange(of: selectedModel?.id, initial: true) {
            guard let tableModel else { return }
            let sheetModel = SheetController(itemController: root.itemController).sheet(for: tableModel.itemId)
            tableSheetModel = TableSheetModel(linkControllable: root.linkControllable, sheetModel: sheetModel, searchText: root.searchModel.searchText)
        }
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
        
        if let tableSheetModel {
            SheetView(model: tableSheetModel)
        }
        //EntryList(itemId: model.itemId)
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
