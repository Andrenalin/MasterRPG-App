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
    @Environment(ListModel.self) private var listModel
    
#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var editMode: EditMode = .inactive
#endif
    
    @Query(filter: #Predicate<PhotoDataModel>{ $0.displayState == 0 }, sort: \PhotoDataModel.name, animation: .smooth) private var items: [PhotoDataModel]
    
    @State private var selected: UUID?
    @State private var listSelection: Set<UUID> = []
    
    var body: some View {
        @Bindable var searchModel = searchModel
        
        let filteredItems = searchModel.searchText.isEmpty ? items : items.filter {
            $0.name.localizedStandardContains(searchModel.searchText) ||
            $0.information.localizedStandardContains(searchModel.searchText)
        }
        
        listView(filteredItems: filteredItems)
            .animation(.smooth, value: filteredItems)
#if os(macOS)
            .importsItemProviders(EditController.importImageTypes, onImport: importImage(_:))
            .onChange(of: selected) {
                model.selectedItem = items.first { $0.id == selected }
                guard let id = model.selectedItem?.id else { return }
                navigator.navigate(to: PhotoRoute.photo(id), method: .push)
            }
#endif
            .onChange(of: listSelection) {
                listModel.update(listSelection: listSelection)
            }
            .onChange(of: listModel.selected) {
                withAnimation {
                    if listModel.selected != model.selectedItem?.id {
                        model.selectedItem = items.first { $0.id == listModel.selected }
                    } else {
                        model.selectedItem = nil
                    }
                }
                guard let id = model.selectedItem?.id else { return }
                if !listSelection.contains(id) {
                    listSelection = Set(arrayLiteral: id)
                }
                navigator.navigate(to: PhotoRoute.detail(id), method: .push)
#if os(iOS)
//                if !listModel.splitList {
//                    withAnimation { listModel.selected = nil }
//                }
#endif
            }
#if os(iOS) || os(visionOS)
            .environment(\.editMode, $editMode)
#endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: filteredItems.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
            .navigationTitle(rootModel.networkModule.title)
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 250)
#endif
            .toolbar {
                if listModel.isSelectionMode {
                    ToolbarItem(placement: .primaryAction) {
                        actionMenu
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            addItem()
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        selectionButton
                    }
                }
            }
    }
    
    @ViewBuilder
    private var actionMenu: some View {
        Menu {
            selectionButton
            
            ItemListContextMenu(controller: ContextMenuMultiController(editController: rootModel.editController, itemController: rootModel.itemController, selection: listModel.selection))
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    private var selectionButton: some View {
        Button {
            listModel.toogleSelectionMode()
#if os(iOS) || os(visionOS)
            editMode = listModel.isSelectionMode ? .active : .inactive
#endif
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
    }
    
    @ViewBuilder
    private var toolSelectionButton: some View {
        if listModel.isSelectionMode {
            selectionButton
                .buttonStyle(.borderedProminent)
        } else {
            selectionButton
        }
    }
    
    private func addItem() {
        let newItem = rootModel.editController.addNew(modelContext: modelContext)
        withAnimation {
            listModel.selected = newItem.id
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
                ItemListContextMenu(controller: ContextMenuMultiController(editController: rootModel.editController, itemController: rootModel.itemController, selection: selection))
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
                .contentShape(.rect)
                .applyIf(!listModel.isSelectionMode) { content in
                    content.contextMenu {
                        ItemListContextMenu(controller: ContextMenuController(editController: rootModel.editController, model: item))
                    }
                }
                .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
        }
        .onDelete(perform: deleteItems)
        .deleteDisabled(listModel.isSelectionMode)
    }
    
    var leadingPadding: CGFloat {
        let value = listModel.isSelectionMode ? 12 : 2
        return CGFloat(valueFor(iOS: value, macOS: 2, tvOS: value, visionOS: value))
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
            .environment(CacheItemListModel())
            .environment(SearchModel.preview)
            .environment(DeviceRotationModel())
    }
    .environment(ListModel())
}
