// @copyright André Trettin

import CoreExternalRPG
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
    @State private var selection: [UUID] = []
    @State private var listSelection: Set<UUID> = []
    @State private var isSelectionMode: Bool = false

    #if !os(macOS)
    @Environment(\.editMode) private var editMode
    #endif
    
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
        .onChange(of: selected) {
            model.selectedItem = items.first { $0.id == selected }
            guard let id = model.selectedItem?.id else { return }
            navigator.navigate(to: SpaceRoute.detail(id), method: .push)
        }
        .navigationTitle("Spaces")
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {  addItem() } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    isSelectionMode.toggle()
#if !os(macOS)
                    if isSelectionMode {
                        editMode?.wrappedValue = .active
                    } else {
                        editMode?.wrappedValue = .inactive
                    }
#endif
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
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
//                    .contextMenu {
//                        ItemListContextMenu(controller: ContextMenuController(editController: rootModel.editController, model: item))
//                    }
            }
            .onDelete(perform: deleteItems)
        }
    }

    private func selectionListView(filteredItems: [SpaceDataModel]) -> some View {
        List(selection: $listSelection) {
            ForEach(filteredItems) { item in
                MainRowView(model: item)
            }
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
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

//                    .selectListItem {
//                        if listSelection.contains(item.id) {
//                            listSelection.remove(item.id)
//                        } else {
//                            listSelection.insert(item.id)
//                        }
//
//                        if let index = selection.firstIndex(of: item.id) {
//                            selection.remove(at: index)
//                        } else {
//                            selection.append(item.id)
//                        }
//                    } isSelected: {
//                        listSelection.contains(item.id)
//                    }

