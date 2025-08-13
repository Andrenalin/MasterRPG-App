// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SelectionRootListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioRootModel.self) private var root
    @State private var listModel = ListModel()
    @State private var cacheItemListModel = CacheItemListModel()

    @Query(filter: #Predicate<AudioDataModel>{ $0.displayState == 0 }, sort: \AudioDataModel.name, animation: .smooth) private var items: [AudioDataModel]
    
    var body: some View {
        NavigationStack {
            SelectionListView2()
        }
        .environment(listModel)
        .environment(cacheItemListModel)
    }
}


struct SelectionListView2: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioRootModel.self) private var root

    @Query(filter: #Predicate<AudioDataModel>{ $0.displayState == 0 }, sort: \AudioDataModel.name, animation: .smooth) private var items: [AudioDataModel]
    
    var body: some View {
        ItemSelectionListView(editController: root.editController, items: items, module: AudioDataModel.typeId) { id in
            AudioRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    
    ManagedNavigationStack {
        SelectionRootListView()
    }
}
