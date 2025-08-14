// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct DetailListView<EditController: EditControllable, Row: View>: View where EditController.Model.ID == UUID {
    public init(editController: EditController, menuController: any ItemListContextMenuControllable, listModel: ListModel, parentModel: EditController.Model, items: [EditController.Model], module: NetworkModules, route: @escaping (UUID) -> any NavigationDestination, @ViewBuilder row: @escaping (EditController.Model) -> Row) {
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
    let parentModel: EditController.Model
    let items: [EditController.Model]
    let module: NetworkModules
    let route: (UUID) -> any NavigationDestination
    let row: (EditController.Model) -> Row
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListDisplayModel.self) private var listDisplayModel
    @Environment(SearchModel.self) private var searchModel
    
#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var editMode: EditMode = .inactive
#endif
    
    public var body: some View {
        let _ = Self._printChanges()
        let _ = print("ParentId \(listModel.selectedParentId?.uuidString ?? "not set")")
        listView(filteredItems: totalItems(items: items))
            .frame(minWidth: 250, idealWidth: 350)
            .overlay {
                if items.isEmpty && !searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
#if !os(tvOS)
            .applyIf(listModel.isSelectionMode) { content in
                content.contextMenu(forSelectionType: EditController.Model.ID.self) { selectedItemIDs in
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
            .onAppear {
                listModel.resetListModel()
            }
            .onChange(of: listModel.listSelection) {
                guard !listModel.listSelection.isEmpty else { return }
                listModel.update(selection: listModel.listSelection)
            }
            .onChange(of: listModel.selected) {
                if let id = listModel.selected {
                    if id == EditController.Model.dropItem.id {
                        navigator.navigate(to: route(EditController.Model.dropItem.id), method: .sheet)
                        listModel.update(selection: [])
                    } else {
                        listModel.listSelection <=> Set(arrayLiteral: id)
                        let local = totalItems(items: items)
                        guard let modelId = local.first(where: { $0.id == id })?.model.id else { return }
                        navigator.navigate(to: route(modelId), method: .push)
                    }
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
            MenuDisplayModeToggle(listModel: listModel, listDisplayModel: listDisplayModel, showSelectionButton: false)
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
            CompactDisplayModeToggle(listDisplayModel: listDisplayModel)
            MediumDisplayModeToggle(listDisplayModel: listDisplayModel)
            RegularDisplayModeToggle(listDisplayModel: listDisplayModel)
        }
    }

    func addItemButton(for type: EditControllerAddType) -> some View {
        Button {
            addItem(for: type)
        } label: {
            Label {
                Text(type.title)
            } icon: {
                Image(systemName: type.icon(collection: EditController.Model.collectionCategory.icon))
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
    
    func filteredItems(items: [EditController.Model], withParentFilter: Bool = true) -> [EditController.Model] {
        var filtered = items
        if withParentFilter {
            if listDisplayModel.listMode == .list {
                filtered = filtered.filter { $0.category != .folder && $0.category != EditController.Model.collectionCategory }
            } else {
                filtered = filtered.filter { $0.parentId == listModel.selectedParentId }
            }
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

    @ViewBuilder
    func listView(filteredItems: [ItemListModel<EditController.Model>]) -> some View {
        @Bindable var listModel = listModel
#if os(macOS)
        if listDisplayModel.isSelectionMode {
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
    
    func itemRows(filteredItems: [ItemListModel<EditController.Model>]) -> some View {
        ForEach(filteredItems) { item in
            row(item.model)
                .applyIf(!listModel.isSelectionMode) { content in
                    content.contextMenu {
                        ItemListContextMenu(controller: menuController, currentSelected: item.id)
                    }
                }
                .padding(.leading, CGFloat(item.level * 16))
#if !os(tvOS)
                .dropDestination(for: LinkData.self) { items, _ in
                    addLinks(links: items)
                }
#endif
                .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
                .listRowSeparator(item.isOpen ? .visible : .hidden, edges: .bottom)
        }
        .onDelete(perform: deleteItems)
        .onMove(perform: moveItems)
        .deleteDisabled(listModel.isSelectionMode)
        .moveDisabled(parentModel.category == .folder)
    }
    
    func addLinks(links: [LinkData]) {
        links.forEach { link in
            guard link.module == EditController.Model.typeId else { return }
            withAnimation { editController.addItem(itemId: link.itemId, in: parentModel, folderId: listModel.lastFolderId) }
        }
    }
    
    var leadingPadding: CGFloat {
        let value = listModel.isSelectionMode ? 12 : 8
        return CGFloat(valueFor(iOS: value, macOS: 4, tvOS: value, visionOS: value))
    }
    
    func totalItems(items: [EditController.Model], level: Int = 0, withParentFilter: Bool = true, entryIds: [UUID: UUID] = [:]) -> [ItemListModel<EditController.Model>] {
        var total: [ItemListModel<EditController.Model>] = []
        guard level < 10 else { return total }
        let sorted: [EditController.Model]
        let filtered = filteredItems(items: items, withParentFilter: withParentFilter)
        if parentModel.category == .folder {
            sorted = filtered.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        } else {
            sorted = filtered
        }
        sorted.forEach { item in
            total.append(ItemListModel(id: entryIds[item.id, default: item.id], model: item, isOpen: listModel.isFolderOpen(id: item.id), level: level))
            if item.specialCategory && listModel.isFolderOpen(id: item.id) {
                let (newItems, newEntryIds) = item.subItems
                total.append(contentsOf: totalItems(items: newItems, level: level + 1, withParentFilter: false, entryIds: newEntryIds))
            }
        }
        if total.isEmpty {
            total.append(ItemListModel(id: EditController.Model.dropItem.id, model: EditController.Model.dropItem, isOpen: false, level: level))
        }
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

