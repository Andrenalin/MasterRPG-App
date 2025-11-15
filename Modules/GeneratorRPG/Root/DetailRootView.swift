// @copyright André Trettin

import RPGValues
import RPGTables

import AndrenalinKit
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(GeneratorRootModel.self) private var root
    
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.generator.viewerkWindowId, canShow: true, route: { DetailRoute.viewer($0) })

    @State private var selection: ItemSelectionModel = ItemSelectionModel()
    
    var body: some View {
        ItemDetailRootView(selectedId: selectedId) {
        } editor: {
            Text("Add a reference character")
            
            if let model = selectedModel {
                detailEditorView(model: model)
            }
        } inspector: {
            LinkRootView(type: .inspector)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.inlineViewer(root: root, with: openFileWindowModel.itemId) {
                    openFileWindowModel.showItem = false
                }
            }
        }
        .navigationDestination(for: SelectionCharacterRoute.self) { route in
            route
                .environment(root.editController.selectionReference)
        }
        .environment(openFileWindowModel)
        .environment(root.listController.cacheListItemModel)
    }

    var selectedModel: GeneratorDataModel? {
        root.itemController.model(for: selectedId ?? root.listControllable.listModel.selectedItemId)
    }
    
    @ViewBuilder
    func detailEditorView(model: GeneratorDataModel) -> some View {
        @Bindable var model = model
        Picker(selection: $model.genType) {
            ForEach(GeneratorDataModel.GenType.allCases) { genType in
                Text(genType.title)
                    .tag(genType)
            }
        } label: {
            Text("Generation Type")
        }

        root.characterRoot.viewController.selectionView(root: root.characterRoot, model: root.editController.selectionReference)
            .onChange(of: root.editController.selectionReference.selection) {
                withAnimation { root.editController.add(referenceId: root.editController.selectionReference.itemId, model: model) }
            }
            .onChange(of: model.referenceId, initial: true) {
                withAnimation { root.editController.selectionReference.resetSelection(itemId: model.referenceId) }
            }
    }
}

#Preview(traits: .mockData) {
    DetailRootView(selectedId: MockData.previewId)
}
