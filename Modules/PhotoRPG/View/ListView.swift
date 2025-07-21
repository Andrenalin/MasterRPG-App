// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ListModel.self) private var listModel
    @Environment(PhotoRootModel.self) private var rootModel
    @Environment(SearchModel.self) private var searchModel
        
    @Query(filter: #Predicate<PhotoDataModel>{ $0.displayState == 0 }, sort: \PhotoDataModel.name, animation: .smooth) private var items: [PhotoDataModel]
    
    var body: some View {
        let _ = Self._printChanges()
        let filteredItems = searchModel.searchText.isEmpty ? items : items.filter {
            $0.name.localizedStandardContains(searchModel.searchText) ||
            $0.information.localizedStandardContains(searchModel.searchText)
        }
        CoreRPG.ListView(editController: rootModel.editController, menuController: menuController, items: filteredItems, module: .photo) { id in
            PhotoRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
#if os(macOS)
        .importsItemProviders(EditController.importImageTypes, onImport: importImage(_:))
#endif
    }

    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: rootModel.editController, itemController: rootModel.itemController, listModel: listModel)
    }

#if os(macOS)
    func importImage(_ providers: [NSItemProvider]) -> Bool {
        EditController.importImageFromProviders(providers) { data in
            guard let data = data else { return }
            Task { @MainActor in
                let model = rootModel.editController.addNew(modelContext: modelContext)
                try? await Task.sleep(for: .seconds(0.5))
                withAnimation {
                    rootModel.editController.resetPhoto(data: data, model: model)
                    listModel.update(selection: [model.id])
                }
            }
        }
    }
#endif
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PhotoDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    ManagedNavigationStack {
        ListView()
            .environment(ListSelectionModel<PhotoDataModel>())
            .environment(CacheItemListModel())
            .environment(SearchModel.preview)
            .environment(DeviceRotationModel())
    }
    .environment(ListModel())
}
