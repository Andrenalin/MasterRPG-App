// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct DetailListView<Model: ListItemFolderable, EditController: EditControllable, Row: View>: View where Model.ID == UUID, Model == EditController.Model {
    public init(editController: EditController, menuController: any ItemListContextMenuControllable, listModel: ListModel, parentModel: Model, items: [Model], module: NetworkModules, route: @escaping (UUID) -> any NavigationDestination, row: @escaping (Model) -> Row) {
        self.editController = editController
        self.menuController = menuController
        self.listModel = listModel
        self.parentModel = parentModel
        self.items = items
        self.module = module
        self.route = route
        self.row = row
    }
    let editController: EditController
    let menuController: ItemListContextMenuControllable
    let listModel: ListModel
    let parentModel: Model
    let items: [Model]
    let module: NetworkModules
    let route: (UUID) -> any NavigationDestination
    let row: (Model) -> Row
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(SearchModel.self) private var searchModel
    
#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var editMode: EditMode = .inactive
#endif
    
    public var body: some View {
        listView(filteredItems: totalItems(items: items))
            .overlay {
                if items.isEmpty && !searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
#if !os(tvOS)
            .applyIf(listModel.isSelectionMode) { content in
                content.contextMenu(forSelectionType: Model.ID.self) { selectedItemIDs in
                    ItemListContextMenu(controller: menuController)
                }
            }
#endif
            .animation(.smooth, value: items.count)
#if os(iOS) || os(visionOS)
            .environment(\.editMode, $editMode)
#endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: items.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
            .onChange(of: listModel.listSelection) {
                guard !listModel.listSelection.isEmpty else { return }
                listModel.update(selection: listModel.listSelection)
            }
            .onChange(of: listModel.selected) {
                if let id = listModel.selected {
                    listModel.listSelection <=> Set(arrayLiteral: id)
                    navigator.navigate(to: route(id), method: .push)
                } else {
                    listModel.resetListSelection()
                }
            }
#if os(iOS) || os(visionOS)
            .onChange(of: listModel.isSelectionMode) {
                editMode = listModel.isSelectionMode ? .active : .inactive
            }
#endif
            .toolbar {
#if os(macOS)
                ToolbarItem(placement: .secondaryAction) {
                    actionMenu
                }
#else
                ToolbarItemGroup(placement: secondaryMenuPlacement) {
                    secondaryActionMenu
                }
#endif
                
                if listModel.isSelectionMode {
                    ToolbarItem(placement: .primaryAction) {
                        MenuSelectionButtonView(listModel: listModel)
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        addItemButton(for: .item)
                    }
                }
            }
    }
}

private extension DetailListView {
    @ViewBuilder
    var actionMenu: some View {
        Menu {
            MenuDisplayModeToggle(listModel: listModel, showSelectionButton: false)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    @ViewBuilder
    var secondaryActionMenu: some View {
        if !listModel.isSelectionMode {
            MenuSelectionButtonView(listModel: listModel)
        }
        ControlGroup {
            addItemButton(for: .folder)
            addItemButton(for: .collection)
        }
        ControlGroup {
            CompactDisplayModeToggle(listModel: listModel)
            MediumDisplayModeToggle(listModel: listModel)
            RegularDisplayModeToggle(listModel: listModel)
        }
    }

    func addItemButton(for type: EditControllerAddType) -> some View {
        Button {
            addItem(for: type)
        } label: {
            Label {
                Text(type.title)
            } icon: {
                Image(systemName: type.icon(collection: "plus"))
            }
        }
    }
    
    func addItem(for type: EditControllerAddType) {
        let newItem = editController.addNew(modelContext: modelContext, type: type)
        withAnimation {
            editController.addItem(itemId: newItem.id, in: modelContext, parentId: listModel.selectedParentId, folderId:  listModel.lastFolderId)
            listModel.selected = newItem.id
        }
    }
    
    func deleteItems(offsets: IndexSet) {
        editController.removeItem(offsets: offsets, model: parentModel)
    }
    
    func moveItems(source: IndexSet, destination: Int) {
        editController.moveItems(source: source, destination: destination, model: parentModel)
    }
    
    @ViewBuilder
    func listView(filteredItems: [Model]) -> some View {
        @Bindable var listModel = listModel
#if os(macOS)
        if listModel.isSelectionMode {
            List(selection: $listModel.listSelection) {
                itemRows(filteredItems: filteredItems)
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
    
    func itemRows(filteredItems: [Model]) -> some View {
        ForEach(filteredItems) { item in
            row(item)
                .applyIf(!listModel.isSelectionMode) { content in
                    content.contextMenu {
                        ItemListContextMenu(controller: menuController, currentSelected: item.id)
                    }
                }
                .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
#if !os(tvOS)
                .dropDestination(for: LinkData.self) { items, _ in
                    addLinks(links: items)
                }
#endif
        }
        .onDelete(perform: deleteItems)
        .onMove(perform: moveItems)
        .deleteDisabled(listModel.isSelectionMode)
        .moveDisabled(parentModel.category == .folder)
    }
    
    func addLinks(links: [LinkData]) {
        links.forEach { link in
            guard link.module == Model.typeId else { return }
            withAnimation { editController.addItem(itemId: link.itemId, in: parentModel, folderId: listModel.lastFolderId) }
        }
    }
    
    var leadingPadding: CGFloat {
        let value = listModel.isSelectionMode ? 12 : 8
        return CGFloat(valueFor(iOS: value, macOS: 4, tvOS: value, visionOS: value))
    }
    
    func totalItems(items: [Model]) -> [Model] {
        var total: [Model] = []
        let sorted: [Model]
        if parentModel.category == .folder {
            sorted = items.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        } else {
            sorted = items
        }
        sorted.forEach { item in
            total.append(item)
            if item.isFolder && listModel.subItemModels[item.id]?.isOpen ?? false {
                total.append(contentsOf: totalItems(items: item.subItems))
            }
        }
        #if !os(tvOS)
        if total.isEmpty {
            #if os(iOS) || os(visionOS)
            if horizontalSizeClass != .compact {
                total.append(Model.dropItem)
            }
            #else
            total.append(Model.dropItem)
            #endif
            
        }
        #endif
        return total
    }

    var secondaryMenuPlacement: ToolbarItemPlacement {
#if os(tvOS)
        .automatic
#else
        .secondaryAction
#endif
    }
}

