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
    @Environment(DiceRootModel.self) private var root

    @Query(filter: #Predicate<DiceDataModel>{ $0.displayState == 0 }, sort: \DiceDataModel.name, animation: .smooth) private var items: [DiceDataModel]
    
    var body: some View {
        ItemSelectionListView(editController: root.editController, items: items, module: DiceDataModel.typeId) { id in
            DiceRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [DiceDataModel]
    
    ManagedNavigationStack {
        SelectionRootView()
    }
}
