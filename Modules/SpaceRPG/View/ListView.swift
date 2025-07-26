// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ListModel.self) private var listModel
    @Environment(SpaceRootModel.self) private var root
    @Environment(SearchModel.self) private var searchModel

    @Query(filter: #Predicate<SpaceDataModel>{ $0.displayState == 0 }, sort: \SpaceDataModel.name, animation: .smooth) private var items: [SpaceDataModel]

    var body: some View {
        let filteredItems = searchModel.searchText.isEmpty ? items : items.filter {
            $0.name.localizedStandardContains(searchModel.searchText) ||
            $0.information.localizedStandardContains(searchModel.searchText)
        }
        CoreRPG.ListView(editController: root.editController, menuController: menuController, items: filteredItems, module: SpaceDataModel.typeId) { id in
            SpaceRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
    }
    
    private var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    ManagedNavigationStack {
        ListView()
            .environment(CacheItemListModel())
            .environment(SearchModel.preview(modelContext: modelContext, module: SpaceDataModel.typeId))
            .environment(DeviceRotationModel())
    }
    .environment(ListModel())
}
