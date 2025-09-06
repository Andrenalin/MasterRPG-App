// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(MapRootModel.self) private var root
    
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
    }
    
    var selectedModel: ItemDataModel? {
        root.listControllable.selectedModel(for: selectedId, modelContext: modelContext)
    }

    var tableModel: MapDataModel? {
        root.itemController.model(for: selectedId ?? root.listControllable.listModel.selectedItemId)
    }

    @ViewBuilder
    func detailEditorView(model: MapDataModel) -> some View {
            root.photoRoot.viewController.selectionView(root: root.photoRoot, model: root.editController.selectionPhoto)
                .onChange(of: root.editController.selectionPhoto.selection) {
                    withAnimation { root.editController.add(photoId: root.editController.selectionPhoto.itemId, model: model) }
                }
                .onChange(of: model.photoId, initial: true) {
                    withAnimation { root.editController.selectionPhoto.resetSelection(itemId: model.photoId) }
                }
            
            EntryList(itemId: model.itemId)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [ItemDataModel]
    @Previewable @Environment(MapRootModel.self) var root
    
    NavigationStack {
        DetailRootView(selectedId: MockData.previewId)
    }
    .onAppear {
        root.listControllable.update(items: models, parentModel: nil)
        root.listControllable.listModel.set(selectedItemId: models.first!.id)
    }
}
