// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import PhotoRPG

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
                        detailEditorView(model: weatherModel)
                    }
#else
                    detailEditorView(model: tableModel)
#endif
                }
            }
        } inspector: {
            //root.diceRoot.viewController.linkWindow(isInspector: true)
        }
        .navigationDestination(for: SelectionPhotoRoute.self) { route in
            route
                .environment(root.editController.selectionPhoto)
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
