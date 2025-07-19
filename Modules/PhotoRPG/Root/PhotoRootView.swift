// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct PhotoRootView: View {
    let withoutNavigation: Bool

    @State private var cacheItemListModel = CacheItemListModel()
    @State private var searchModel = SearchModel()
    @State private var selectionModel = ListSelectionModel<PhotoDataModel>()

    var body: some View {
        RootView(module: .space, selectionModel: selectionModel, withoutNavigation: withoutNavigation, list: {
            ListView()
        }, detail: {
            if let selected = selectionModel.selectedItem {
                DetailView(model: selected)
            }
        })
        .environment(cacheItemListModel)
        .environment(searchModel)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    ManagedNavigationStack {
        PhotoRootView(withoutNavigation: true)
            .environment(TabTitleModel())
            .environment(DeviceRotationModel())
    }
    .environment(PhotoRootModel(modelContext: modelContext))
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    PhotoRootView(withoutNavigation: false)
        .environment(TabTitleModel())
        .environment(DeviceRotationModel())
        .environment(PhotoRootModel(modelContext: modelContext))
}
