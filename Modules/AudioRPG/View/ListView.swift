// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ListModel.self) private var listModel
    @Environment(AudioRootModel.self) private var root
    @Environment(SearchModel.self) private var searchModel
        
    @Query(filter: #Predicate<AudioDataModel>{ $0.displayState == 0 }, sort: \AudioDataModel.name, animation: .smooth) private var items: [AudioDataModel]
    
    var body: some View {
        let _ = Self._printChanges()
        let filteredItems = searchModel.searchText.isEmpty ? items : items.filter {
            $0.name.localizedStandardContains(searchModel.searchText) ||
            $0.information.localizedStandardContains(searchModel.searchText)
        }
        CoreRPG.ListView(editController: root.editController, menuController: menuController, items: filteredItems, module: AudioDataModel.typeId) { id in
            AudioRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
    }

    private var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    ManagedNavigationStack {
        ListView()
            .environment(CacheItemListModel())
            .environment(SearchModel.preview)
            .environment(DeviceRotationModel())
    }
    .environment(ListModel())
}
