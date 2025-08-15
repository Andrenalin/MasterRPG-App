// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SelectionRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var listModel = ListModel()
    @State private var cacheItemListModel = CacheItemListModel()

    var body: some View {
        NavigationStack {
            SelectionListView()
        }
        .environment(listModel)
        .environment(cacheItemListModel)
    }
}

struct SelectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PhotoRootModel.self) private var root

    @Query(filter: #Predicate<PhotoDataModel>{ $0.displayState == 0 }, sort: \PhotoDataModel.name, animation: .smooth) private var items: [PhotoDataModel]
    
    var body: some View {
        ItemSelectionListView(editController: root.editController, items: items, module: PhotoDataModel.typeId) { id in
            PhotoRoute.detail(id)
        } row: { itemId in
            if let model = root.itemController.modelSync(for: itemId) {
                MainRowView(model: model)
            }
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    
    ManagedNavigationStack {
        SelectionRootView()
    }
}
