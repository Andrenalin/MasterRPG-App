// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListSelectionModel<SpaceDataModel>.self) private var model
    @Environment(SpaceRootModel.self) private var rootModel
    @Environment(SearchModel.self) private var searchModel

    @Query(filter: #Predicate<SpaceDataModel>{ $0.displayState == 0 }, sort: \SpaceDataModel.name, animation: .smooth) private var items: [SpaceDataModel]

    @State private var selected: UUID?
    @State private var selection: Set<UUID> = []
    @State private var isSelectionMode: Bool = false

    var body: some View {
        @Bindable var searchModel = searchModel

        let filteredItems = searchModel.searchText.isEmpty ? items : items.filter {
            $0.name.localizedStandardContains(searchModel.searchText) ||
            $0.information.localizedStandardContains(searchModel.searchText)
        }

        Group {
            if isSelectionMode {
                selectionListView(filteredItems: filteredItems)
            } else {
                listView(filteredItems: filteredItems)
            }
        }
        .navigationDestination(for: SpaceRoute.self) { route in
            route
                .environment(rootModel)
                .environment(cacheItemListModel)
        }
        .animation(.smooth, value: filteredItems)
        .animation(.snappy, value: isSelectionMode)
        .scrollBounceBehavior(.basedOnSize)
#if os(macOS)
        .importsItemProviders(EditController.importImageTypes, onImport: importImage(_:))
#endif
        .onChange(of: selected) {
            print("Seleccted Change: \(selected)")
            model.selectedItem = items.first { $0.id == selected }
            print("Change as well: \(model.selectedItem)")
            guard let id = model.selectedItem?.id else { return }
            print("Change as id: \(id)")
            navigator.navigate(to: SpaceRoute.photo(id), method: .push)
        }
        .navigationTitle("Photos")
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {  addItem() } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    isSelectionMode.toggle()
                } label: {
                    Label("Change Mode to \(isSelectionMode ? "Off" : "On")", systemImage: "list.bullet")
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                Button {
                    isSelectionMode.toggle()
                } label: {
                    Label("Some", systemImage: "gear")
                }
            }
        }
    }
    
    private func addItem() {
        let newItem = rootModel.editController.addNew(modelContext: modelContext)
        withAnimation {
            selected = newItem.id
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }

    private func listView(filteredItems: [SpaceDataModel]) -> some View {
        List(selection: $selected) {
            ForEach(filteredItems) { item in
                MainRowView(model: item)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .contextMenu {
                        ItemListContextMenu(controller: ContextMenuController(editController: rootModel.editController, model: item))
                    }
            }
            .onDelete(perform: deleteItems)
        }
    }

    private func selectionListView(filteredItems: [SpaceDataModel]) -> some View {
        List(selection: $selection) {
            ForEach(filteredItems) { item in
                MainRowView(model: item)
                    .selectListItem {
                        if selection.contains(item.id) {
                            selection.remove(item.id)
                        } else {
                            selection.insert(item.id)
                        }
                    } isSelected: {
                        selection.contains(item.id)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
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
                    selected = model.id
                }
            }
        }
    }
#endif
}

#Preview(traits: .mockData) {
    @Previewable @Query var photos: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    ManagedNavigationStack {
        ListView()
            .environment(ListSelectionModel<SpaceDataModel>())
            .environment(SpaceRootModel(modelContext: modelContext))
            .environment(CacheItemListModel())
            .environment(SearchModel.preview)
            .environment(DeviceRotationModel())
    }
}

