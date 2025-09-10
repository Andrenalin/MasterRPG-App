// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(CharacterRootModel.self) private var root
    
    @State private var openFileWindowModel = OpenFileWindowModel()
    
    var body: some View {
        CoreRPG.DetailRootView(selectedId: selectedId) {
        } editor: {
                if let tableModel {
                    detailEditorView(model: tableModel)
                }
        } inspector: {
            root.diceRoot.viewController.linkWindow(root: root.diceRoot, isInspector: true)
        }
        .navigationDestination(for: SelectionDiceRoute.self) { route in
            route
                .environment(root.editController.selectionDice)
        }
        .environment(openFileWindowModel)
    }
    
    var selectedModel: ItemDataModel? {
        root.listControllable.selectedModel(for: selectedId, modelContext: modelContext)
    }

    var tableModel: CharacterDataModel? {
        root.itemController.model(for: selectedId ?? root.listControllable.listModel.selectedItemId)
    }

    @ViewBuilder
    func detailEditorView(model: CharacterDataModel) -> some View {
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
    @Previewable @Environment(CharacterRootModel.self) var root
    
    NavigationStack {
        DetailRootView(selectedId: MockData.previewId)
    }
    .onAppear {
        root.listControllable.update(items: models, parentModel: nil)
        root.listControllable.listModel.set(selectedItemId: models.first!.id)
    }
}
