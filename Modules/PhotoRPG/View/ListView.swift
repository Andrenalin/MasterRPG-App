// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListSelectionModel<PhotoDataModel>.self) private var model
    @Environment(PhotoRootModel.self) private var rootModel
    @Environment(SearchModel.self) private var searchModel
    
#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.editMode) private var editMode
#endif
    
    @Query(filter: #Predicate<PhotoDataModel>{ $0.displayState == 0 }, sort: \PhotoDataModel.name, animation: .smooth) private var items: [PhotoDataModel]
    
    @State private var selected: UUID?
    @State private var selection: [UUID] = []
    @State private var listSelection: Set<UUID> = []
    @State private var isSelectionMode: Bool = false
    
    var body: some View {
        @Bindable var searchModel = searchModel
        
        let filteredItems = searchModel.searchText.isEmpty ? items : items.filter {
            $0.name.localizedStandardContains(searchModel.searchText) ||
            $0.information.localizedStandardContains(searchModel.searchText)
        }
        
        listView(filteredItems: filteredItems)
        .navigationDestination(for: PhotoRoute.self) { route in
            route
                .environment(rootModel)
                .environment(cacheItemListModel)
        }
        .animation(.smooth, value: filteredItems)
#if os(macOS)
        .importsItemProviders(EditController.importImageTypes, onImport: importImage(_:))
        .onChange(of: selected) {
            model.selectedItem = items.first { $0.id == selected }
            guard let id = model.selectedItem?.id else { return }
            navigator.navigate(to: PhotoRoute.photo(id), method: .push)
        }
#endif
        .onChange(of: selection) {
            guard !isSelectionMode else { return }
            let selected = items.first { $0.id == selection.first }
            withAnimation {
                if selected != model.selectedItem {
                    model.selectedItem = selected
                } else {
                    model.selectedItem = nil
                }
            }
            guard let id = model.selectedItem?.id else { return }
            navigator.navigate(to: PhotoRoute.photo(id), method: .push)
#if os(iOS)
            if horizontalSizeClass == .compact {
                //                    withAnimation { selection.removeAll() }
            }
#endif
        }
#if os(iOS) || os(visionOS)
        .onChange(of: editMode) {
            if editMode?.wrappedValue == .active {
                isSelectionMode = true
            } else {
                isSelectionMode = false
            }
        }
#endif
        .navigationTitle("Photos")
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {  addItem() } label: {
                    Label("Add", systemImage: "plus")
                }
            }
#if os(macOS)
            ToolbarItem(placement: .automatic) {
                if isSelectionMode {
                    Button {
                        isSelectionMode.toggle()
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        isSelectionMode.toggle()
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                }
        }
#endif

#if os(iOS) || os(visionOS)
            ToolbarItem(placement: .automatic) {
                EditButton()
            }
#endif
        }
    }
    
    private func addItem() {
        let newItem = rootModel.editController.addNew(modelContext: modelContext)
        withAnimation {
            selection = [newItem.id]
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                rootModel.editController.delete(model: items[index])
            }
        }
    }
    
    @ViewBuilder
    private func listView(filteredItems: [PhotoDataModel]) -> some View {
#if os(macOS)
        if isSelectionMode {
            List(selection: $listSelection) {
                itemRows(filteredItems: filteredItems)
            }
            .contextMenu {
                ItemListContextMenu(controller: ContextMenuController(editController: rootModel.editController, model: PhotoDataModel()))
            }
        } else {
            List(selection: $selected) {
                itemRows(filteredItems: filteredItems)
            }
        }
#else
        List(selection: $listSelection) {
            itemRows(filteredItems: filteredItems)
        }
#endif
        
    }
    
    private func itemRows(filteredItems: [PhotoDataModel]) -> some View {
        ForEach(filteredItems) { item in
            MainRowView(model: item)
                .contextMenu {
                    if !isSelectionMode {
                        ItemListContextMenu(controller: ContextMenuController(editController: rootModel.editController, model: item))
                    }
                }
                .listRowInsets(EdgeInsets(top: 2, leading: valueFor(iOS: isSelectionMode ? 12 : 2, macOS: 2, tvOS: isSelectionMode ? 12 : 2, visionOS: isSelectionMode ? 12 : 2), bottom: 2, trailing: 0))
        }
        .onDelete(perform: deleteItems)
        .deleteDisabled(isSelectionMode)
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
                    selection = [model.id]
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
            .environment(PhotoRootModel(modelContext: modelContext))
            .environment(CacheItemListModel())
            .environment(SearchModel.preview)
            .environment(DeviceRotationModel())
    }
}

