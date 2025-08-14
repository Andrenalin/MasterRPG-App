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
    @Environment(PdfRootModel.self) private var root

    @Query(filter: #Predicate<PdfDataModel>{ $0.displayState == 0 }, sort: \PdfDataModel.name, animation: .smooth) private var items: [PdfDataModel]
    
    var body: some View {
        ItemSelectionListView(editController: root.editController, items: items, module: PdfDataModel.typeId) { id in
            PdfRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PdfDataModel]
    
    ManagedNavigationStack {
        SelectionRootView()
    }
}
