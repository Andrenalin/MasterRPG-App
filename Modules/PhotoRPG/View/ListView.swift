// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ListModel.self) private var listModel
    @Environment(PhotoRootModel.self) private var root
    @Environment(SearchModel.self) private var searchModel
        
    @Query(filter: #Predicate<PhotoDataModel>{ $0.displayState == 0 }, sort: \PhotoDataModel.name, animation: .smooth) private var items: [PhotoDataModel]
    
    var body: some View {
        CoreRPG.ListView(editController: root.editController, menuController: menuController, items: filteredItems, module: PhotoDataModel.typeId) { id in
            PhotoRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
#if !os(tvOS)
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: FileController.fileTypes, updateFile: updateFile))
#endif
#if os(macOS)
        .importsItemProviders(EditController.importImageTypes, onImport: importImage(_:))
#endif
    }

    private var filteredItems: [PhotoDataModel] {
        var filtered = items
        if searchModel.searchToken != ItemListCategory.all {
            filtered = filtered.filter { $0.category == searchModel.searchToken }
        }
        if !searchModel.selectedTokens.isEmpty {
            let selectedTags = searchModel.selectedTokens.map { $0.tag }
            filtered = filtered.filter { $0.tags.contains(selectedTags) }
        }
        guard !searchModel.searchText.isEmpty else { return filtered }
        return filtered.filter {
            $0.name.localizedStandardContains(searchModel.searchText) ||
            $0.information.localizedStandardContains(searchModel.searchText)
        }
    }
    
    private var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editController, itemController: root.itemController, listModel: listModel)
    }

    private func updateFile(url: URL) {
        Task { @MainActor in
            let model = root.editController.addNew(modelContext: modelContext, type: .item)
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation {
                root.editController.resetFile(url: url, in: model)
                listModel.update(selection: [model.id])
            }
        }
    }

#if os(macOS)
    nonisolated private func importImage(_ providers: [NSItemProvider]) -> Bool {
        EditController.importImageFromProviders(providers) { data in
            guard let data = data else { return }
            Task { @MainActor in
                let model = root.editController.addNew(modelContext: modelContext)
                try? await Task.sleep(for: .seconds(0.5))
                withAnimation {
                    root.editController.resetFile(data: data, model: model)
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
            .environment(CacheItemListModel())
            .environment(SearchModel.preview(modelContext: modelContext, module: PhotoDataModel.typeId))
            .environment(DeviceRotationModel())
    }
    .environment(ListModel())
}
