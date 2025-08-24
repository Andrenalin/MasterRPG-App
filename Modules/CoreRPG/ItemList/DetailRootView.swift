// @copyright André Trettin

import SwiftData
import SwiftUI

public struct DetailRootView<Header: View>: View {
    public init(@ViewBuilder header: () -> Header) {
        self.header = header()
    }
    
    let header: Header
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListDisplayModel.self) private var listDisplayModel
    @Environment(SearchModel.self) private var searchModel
    
    @Environment(ItemRootController.self) private var root
    
    @State private var selection = GroupItemSelectionModel()
    @State private var openFileWindowModel = OpenFileWindowModel()

    public var body: some View {
        let _ = Self._printChanges()
        
        if let selectedModel {
            ItemDetailEditorView(root: root, model: selectedModel) {
                header
            }
            .environment(selection)
            .environment(openFileWindowModel)
        }
//        DetailView(model: model)
//            .navigationDestination(for: DetailRoute.self) { route in
//                route
//                    .environment(cacheItemListModel)
//                    .environment(listDisplayModel)
//                    .environment(searchModel)
//            }
    }
    
    var selectedModel: ItemDataModel? {
        root.listControllable.listModel.selectedModel
    }
}

//#Preview("Folder", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    @Previewable @Query var models: [ItemDataModel]
//    
//    DetailRootView(model: models.first(where: { $0.id == MockData.folderId })!)
//}
//
//#Preview("Collection", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    @Previewable @Query var models: [ItemDataModel]
//    
//    DetailRootView(model: models.first(where: { $0.id == MockData.playlistId })!)
//}
//
//#Preview("Item", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    @Previewable @Query var models: [ItemDataModel]
//    
//    DetailRootView(model: models.first(where: { $0.id == MockData.previewId })!)
//}
