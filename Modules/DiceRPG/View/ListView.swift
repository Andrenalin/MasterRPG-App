// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ListModel.self) private var listModel
    @Environment(DiceRootModel.self) private var root
    @Environment(SearchModel.self) private var searchModel
        
    @Query(filter: #Predicate<DiceDataModel>{ $0.displayState == 0 }, sort: \DiceDataModel.name, animation: .smooth) private var items: [DiceDataModel]
    
    var body: some View {
        ItemListView(editController: root.editController, menuController: menuController, items: items, module: DiceDataModel.typeId) { id in
            DiceRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
    }

    private var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        ListView()
    }
}
