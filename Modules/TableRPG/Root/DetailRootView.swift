// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(TableRootModel.self) private var root
    
    var body: some View {
        CoreRPG.DetailRootView(selectedId: selectedId) {
        } editor: {
            if let selectedModel {
                if let tableModel {
                    if !selectedModel.specialCategory {
                        // OpenFileWindowView(model: openFileWindowModel, module: root.module, windowId: WindowIdentifier.pdfViewer.rawValue, route: DetailRoute.viewer(selection.selectedItem ?? model.id))
                    }
#if os(macOS)
                    ScrollView {
                        detailEditorView(model: tableModel)
                    }
#else
                    detailEditorView(model: tableModel)
#endif
                }
            }
        } inspector: {
            root.diceRoot.viewController.linkWindow(root: root.diceRoot, isInspector: true)
        }
        .navigationDestination(for: SelectionDiceRoute.self) { route in
            route
                .environment(root.editController.selectionDice)
        }
    }
    
    var selectedModel: ItemDataModel? {
        root.listControllable.selectedModel(for: selectedId, modelContext: modelContext)
    }

    var tableModel: TableDataModel? {
        root.itemController.model(for: selectedId ?? root.listControllable.listModel.selectedItemId)
    }

    func detailEditorView(model: TableDataModel) -> some View {
        Form {
            root.diceRoot.viewController.selectionView(root: root.diceRoot, model: root.editController.selectionDice)
                .onChange(of: root.editController.selectionDice.itemId) {
                    model.diceId <=> root.editController.selectionDice.itemId
                }
                .onChange(of: model.diceId, initial: true) {
                    guard model.diceId != root.editController.selectionDice.itemId else { return }
                    if let diceId = model.diceId {
                        root.editController.selectionDice.toggleSelection(itemId: diceId, isCollection: false)
                    } else {
                        root.editController.selectionDice.selection = []
                    }
                }
            Text("Empty - comming soon")
        }
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
