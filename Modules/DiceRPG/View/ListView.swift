// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DiceRootModel.self) private var root

    @Query(filter: #Predicate<DiceDataModel>{ $0.displayState == 0 }, sort: \DiceDataModel.name, animation: .smooth) private var items: [DiceDataModel]
    
    var body: some View {
        ItemListView(listController: root.listController, editController: root.editController, menuController: menuController, parentModel: nil, module: DiceDataModel.typeId) { id in
            DiceRoute.detail(id)
        } row: { itemId in
            if let model = root.itemController.modelSync(for: itemId) {
                MainRowView(model: model)
            }
        }
        .onChange(of: items, initial: true) {
            withAnimation { root.listController.update(items: items) }
        }
    }
}

private extension ListView {
    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: root.listController.listModel)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        ListView()
    }
}
