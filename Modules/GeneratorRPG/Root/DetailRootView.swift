// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(GeneratorRootModel.self) private var root
    
    @State private var openFileWindowModel = OpenFileWindowModel()

    @State private var selection: ItemSelectionModel = ItemSelectionModel()
    
    var body: some View {
        ItemDetailRootView(selectedId: selectedId) {
        } editor: {
            Text("Add a reference character")
            
            if let _ = selectedModel {
//                root.characterRoot.viewController.selectionView(root: root.characterRoot, model: selection)
            }
        }
        .environment(openFileWindowModel)
        .environment(root.listController.cacheListItemModel)
    }
    
    var selectedModel: ItemDataModel? {
        root.listControllable.selectedModel(for: selectedId, modelContext: modelContext)
    }
}

#Preview(traits: .mockData) {
    DetailRootView(selectedId: MockData.previewId)
}
