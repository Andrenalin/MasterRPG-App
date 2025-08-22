// @copyright André Trettin

import SwiftData
import SwiftUI

struct DetailRootView: View {
    let model: ItemDataModel
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListDisplayModel.self) private var listDisplayModel
    @Environment(SearchModel.self) private var searchModel
    
    @Environment(ItemRootController.self) private var root
    
    @State private var selection = GroupItemSelectionModel()
    @State private var openFileWindowModel = OpenFileWindowModel()

    var body: some View {
        ItemDetailEditorView(root: root, model: model)
        .environment(selection)
        .environment(openFileWindowModel)

//        DetailView(model: model)
//            .navigationDestination(for: DetailRoute.self) { route in
//                route
//                    .environment(cacheItemListModel)
//                    .environment(listDisplayModel)
//                    .environment(searchModel)
//            }
    }
}

#Preview("Folder", traits: .mockData) {
    @Previewable @Environment(FakeItemRootController.self) var root
    @Previewable @Query var models: [ItemDataModel]
    
    DetailRootView(model: models.first(where: { $0.id == MockData.folderId })!)
}

#Preview("Collection", traits: .mockData) {
    @Previewable @Environment(FakeItemRootController.self) var root
    @Previewable @Query var models: [ItemDataModel]
    
    DetailRootView(model: models.first(where: { $0.id == MockData.playlistId })!)
}

#Preview("Item", traits: .mockData) {
    @Previewable @Environment(FakeItemRootController.self) var root
    @Previewable @Query var models: [ItemDataModel]
    
    DetailRootView(model: models.first(where: { $0.id == MockData.previewId })!)
}
