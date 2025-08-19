// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SelectionRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var cacheItemListModel = CacheItemListModel()

    var body: some View {
        NavigationStack {
            SelectionListView()
        }
        .environment(cacheItemListModel)
    }
}

struct SelectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DiceRootModel.self) private var root

    @Query(filter: #Predicate<DiceDataModel>{ $0.displayState == 0 }, sort: \DiceDataModel.name, animation: .smooth) private var items: [DiceDataModel]
    
    var body: some View {
        ItemSelectionListView(listController: root.listLinkController, parentModel: nil, module: DiceDataModel.typeId) { id in
            DiceRoute.detail(id)
        } row: { itemId in
            if let model = root.itemController.modelSync(for: itemId) {
                MainRowView(model: model)
            }
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]
    
    ManagedNavigationStack {
        SelectionRootView()
    }
}
