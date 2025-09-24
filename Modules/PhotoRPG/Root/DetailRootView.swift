// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailRootView: View {
    let selectedId: UUID?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(PhotoRootModel.self) private var root
    
    @State private var openFileWindowModel = OpenFileWindowModel()
    
    var body: some View {
        ItemDetailRootView(selectedId: selectedId) {
        } editor: {
            if let model = selectedModel {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        GroupedPhotoView(cacheController: root.cacheController, model: model)
                            .stretchy()
                    }
                }
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
    @Previewable @Query var models: [ItemDataModel]
    @Previewable @Environment(PhotoRootModel.self) var root
    
    NavigationStack {
        DetailRootView(selectedId: MockData.previewId)
    }
    .onAppear {
        root.listControllable.update(items: models, parentModel: nil)
        root.listControllable.listModel.set(selectedItemId: MockData.previewId3)
    }
}
