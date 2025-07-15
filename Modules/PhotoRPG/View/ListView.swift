// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator

    @Environment(ListSelectionModel<PhotoDataModel>.self) private var model
    @Environment(PhotoRootModel.self) private var rootModel
    @Environment(SearchModel.self) private var searchModel

    @Query(filter: #Predicate<PhotoDataModel>{ $0.displayState == 0 }, sort: \PhotoDataModel.name, animation: .smooth) private var items: [PhotoDataModel]

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
        .navigationDestination(for: PhotoRoute.self) { route in
            route
        }
        .animation(.smooth, value: filteredItems)
        .animation(.snappy, value: isSelectionMode)
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: selected) {
            model.selectedItem = items.first { $0.id == selected }
            guard let selected = model.selectedItem else { return }
            navigator.navigate(to: PhotoRoute.photo(selected.id), method: .push)
        }
        .navigationTitle("Photos")
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addItem) {
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
        withAnimation {
            let newItem = PhotoDataModel(name: " New ", information: "", category: .character, tags: [])
            modelContext.insert(newItem)
            try? modelContext.save()
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

    private func listView(filteredItems: [PhotoDataModel]) -> some View {
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

    private func selectionListView(filteredItems: [PhotoDataModel]) -> some View {
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
}
