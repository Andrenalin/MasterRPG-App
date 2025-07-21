// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct SpaceRootView: View {
    let withoutNavigation: Bool
    
    @State private var cacheItemListModel = CacheItemListModel()
    @State private var listModel = ListModel()
    @State private var searchModel = SearchModel()
    @State private var selectionModel = ListSelectionModel<SpaceDataModel>()

    var body: some View {
        RootView(module: .space, listModel: listModel, withoutNavigation: withoutNavigation, list: {
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

#Preview("Embed", traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    ManagedNavigationStack {
        SpaceRootView(withoutNavigation: true)
            .environment(TabTitleModel())
            .environment(DeviceRotationModel())
    }
    .environment(SpaceRootModel(modelContext: modelContext))
}

#Preview("Split", traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext

    SpaceRootView(withoutNavigation: false)
        .environment(TabTitleModel())
        .environment(DeviceRotationModel())
        .environment(SpaceRootModel(modelContext: modelContext))
}

