// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct ListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PhotoRootModel.self) private var rootModel
    @Environment(SearchModel.self) private var searchModel
        
    @Query(filter: #Predicate<PhotoDataModel>{ $0.displayState == 0 }, sort: \PhotoDataModel.name, animation: .smooth) private var items: [PhotoDataModel]
    
    var body: some View {
        let _ = Self._printChanges()
        let filteredItems = searchModel.searchText.isEmpty ? items : items.filter {
            $0.name.localizedStandardContains(searchModel.searchText) ||
            $0.information.localizedStandardContains(searchModel.searchText)
        }
        CoreRPG.ListView(items: filteredItems, module: .photo) { id in
            PhotoRoute.detail(id)
        } row: { model in
            MainRowView(model: model)
        }
#if os(macOS)
        .importsItemProviders(EditController.importImageTypes, onImport: importImage(_:))
#endif

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


struct ListOldView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListModel.self) private var listModel
    @Environment(PhotoRootModel.self) private var rootModel
    @Environment(SearchModel.self) private var searchModel
    
#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var editMode: EditMode = .inactive
#endif
    
    @Query(filter: #Predicate<PhotoDataModel>{ $0.displayState == 0 }, sort: \PhotoDataModel.name, animation: .smooth) private var items: [PhotoDataModel]
    
    @State private var selected: UUID?
    
    var body: some View {
        let _ = Self._printChanges()
        
        @Bindable var searchModel = searchModel
        
        let filteredItems = searchModel.searchText.isEmpty ? items : items.filter {
            $0.name.localizedStandardContains(searchModel.searchText) ||
            $0.information.localizedStandardContains(searchModel.searchText)
        }
        
        listView(filteredItems: filteredItems)
            .animation(.smooth, value: filteredItems)
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
            .importsItemProviders(EditController.importImageTypes, onImport: importImage(_:))
            .navigationSplitViewColumnWidth(min: 180, ideal: 250)
#endif
            .onChange(of: listModel.listSelection) {
                guard !listModel.listSelection.isEmpty else { return }
                listModel.update(selection: listModel.listSelection)
            }
            .onChange(of: listModel.selected) {
                if let id = listModel.selected {
                    listModel.listSelection <=> Set(arrayLiteral: id)
                    navigator.navigate(to: PhotoRoute.detail(id), method: .push)
                } else {
                    listModel.resetListSelection()
                }
            }
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
        @Bindable var listModel = listModel
#if os(macOS)
        if listModel.isSelectionMode {
            List(selection: $listModel.listSelection) {
                itemRows(filteredItems: filteredItems)
            }
            .contextMenu {
                ItemListContextMenu(controller: ContextMenuMultiController(editController: rootModel.editController, itemController: rootModel.itemController, selection: listModel.selection))
            }
        } else {
            List(selection: $listModel.selected) {
                itemRows(filteredItems: filteredItems)
            }
        }
#else
        List(selection: $listModel.listSelection) {
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
