// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct PhotoListView: View {
    @Environment(SearchModel.self) private var searchModel
    @Environment(\.modelContext) private var modelContext
    @Environment(ListSelectionModel<PhotoDataModel>.self) private var model

    @Query(sort: \PhotoDataModel.name, animation: .smooth) private var items: [PhotoDataModel]

    @State private var selected: UUID?
    @State private var selection: Set<UUID> = []
    @State private var isSelectionMode: Bool = false

#if os(iOS)
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
        .animation(.smooth, value: filteredItems)
        .animation(.snappy, value: isSelectionMode)
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: selected) {
            model.selectedItem = items.first { $0.id == selected }
        }
#if os(iOS)
        .onChange(of: editMode) {
            isSelectionMode = (editMode?.wrappedValue == .active)
        }
#endif
        .navigationTitle("Photos")
        //.navigationSubtitle("\(filteredItems.count) items (\(items.count) total)")
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
#if os(iOS)
                EditButton()
#else
                Button {
                    isSelectionMode.toggle()
                } label: {
                    Label("Change Mode to \(isSelectionMode ? "Off" : "On")", systemImage: "list.bullet")
                }
#endif
            }
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = PhotoDataModel(name: "\(Date()) Hello", information: "Some more Text ususally longer", category: .character, tags: ["Held", "Meins"], degrees: Double.random(in: 0...360.0))
            modelContext.insert(newItem)
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
                PhotoRow(model: item)
            }
            .onDelete(perform: deleteItems)
        }
    }

    private func selectionListView(filteredItems: [PhotoDataModel]) -> some View {
        List(selection: $selection) {
            ForEach(filteredItems) { item in
                PhotoRow(model: item)
                #if os(macOS)
                    .selectListItem {
                        // some action not needed now
                    } isSelected: {
                        selection.contains(item.id)
                    }
                #endif
            }
        }
    }
}
