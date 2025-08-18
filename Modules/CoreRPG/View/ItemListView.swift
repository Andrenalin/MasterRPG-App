// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct ItemListView<ListController: ListControllable, EditController: EditControllable, Row: View>: View where ListController.Model == EditController.Model, EditController.Model.ID == UUID {
    public init(listController: ListController, editController: EditController, menuController: any ItemListContextMenuControllable, listModel: ListModel, parentModel: EditController.Model? = nil, items: [EditController.Model], module: NetworkModules, route: @escaping (UUID) -> any NavigationDestination, @ViewBuilder row: @escaping (UUID) -> Row) {
        self.listController = listController
        self.editController = editController
        self.menuController = menuController
        self.listModel = listModel
        self.parentModel = parentModel
        self.items = items
        self.module = module
        self.route = route
        self.row = row
    }
    let listController: ListController
    let editController: EditController
    let menuController: ItemListContextMenuControllable
    let listModel: ListModel
    let parentModel: EditController.Model?
    let items: [EditController.Model]
    let module: NetworkModules
    let route: (UUID) -> any NavigationDestination
    let row: (UUID) -> Row
    
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
//        let _ = Self._printChanges()
//        let _ = print("ParentId \(listModel.selectedParentId?.uuidString ?? "not set")")

        listView()
            .frame(minWidth: 250, idealWidth: 350)
            .overlay {
                if totalItems.isEmpty && !searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
#if !os(tvOS)
            .applyIf(listDisplayModel.isSelectionMode) { content in
                content.contextMenu(forSelectionType: EditController.Model.ID.self) { selectedItemIDs in
                    ItemListContextMenu(controller: menuController)
                }
            }
#endif
            .animation(.smooth, value: totalItems.count)
#if os(iOS) || os(visionOS)
            .environment(\.editMode, $editMode)
#endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: totalItems.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
            .applyIf(parentModel == nil) {
                $0.navigationTitle(module.title)
            }
            .onAppear {
                listModel.resetListModel()
            }
            .onChange(of: listDisplayModel.isSelectionMode) {
                listModel.update(selectionMode: listDisplayModel.isSelectionMode)
            }
            .onChange(of: listModel.listSelection) {
                guard !listModel.listSelection.isEmpty else { return }
                guard let id = listModel.listSelection.first else {
                    listModel.selected = nil
                    return
                }
                guard let modelId = totalItems.first(where: { $0.id == id })?.model.id else { return }
                let selection = Set([modelId])
                listModel.update(selection: selection)
            }
            .onChange(of: listModel.selected) {
                if let id = listModel.selected {
                    if id == EditController.Model.dropItem.id {
                        navigator.navigate(to: route(EditController.Model.dropItem.id), method: .sheet)
                        listModel.update(selection: [])
                    } else {
                        listModel.listSelection <=> Set(arrayLiteral: id)
                        navigator.navigate(to: route(id), method: .push)
                    }
                } else {
                    listModel.resetListSelection()
                }
            }
#if os(iOS) || os(visionOS)
            .onChange(of: listDisplayModel.isSelectionMode) {
                editMode = listDisplayModel.isSelectionMode ? .active : .inactive
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
                if listDisplayModel.isSelectionMode {
                    ToolbarItem(placement: .primaryAction) {
                        MenuSelectionButtonView(listDisplayModel: listDisplayModel)
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        addItemButton(for: .item)
                    }
                }
            }
    }
}

private extension ItemListView {
    @ViewBuilder
    var actionMenu: some View {
        Menu {
            MenuDisplayModeToggle(listDisplayModel: listDisplayModel, showSelectionButton: false) {
                if parentModel == nil {
                    addItemButton(for: .folder)
                        .disabled(listDisplayModel.isListMode)
                    addItemButton(for: .collection)
                        .disabled(listDisplayModel.isListMode)
                    Divider()
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    @ViewBuilder
    var secondaryActionMenu: some View {
        if !listDisplayModel.isSelectionMode {
            MenuSelectionButtonView(listDisplayModel: listDisplayModel)
        }
        ControlGroup {
            addItemButton(for: .folder)
            addItemButton(for: .collection)
        }
        .disabled(listDisplayModel.isListMode)
        
        ControlGroup {
            CompactDisplayModeToggle(listDisplayModel: listDisplayModel)
            MediumDisplayModeToggle(listDisplayModel: listDisplayModel)
            RegularDisplayModeToggle(listDisplayModel: listDisplayModel)
        }
        if parentModel == nil {
            ControlGroup {
                ListModeToggle(listDisplayModel: listDisplayModel)
                FolderModeToggle(listDisplayModel: listDisplayModel)
            }
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
            if parentModel != nil {
                editController.addItem(itemId: newItem.id, in: modelContext, parentId: listModel.selectedParentId, folderId:  listModel.lastFolderId)
            }
            listModel.selected = newItem.id
        }
    }
    
    func deleteItems(offsets: IndexSet) {
        if let parentModel {
            editController.removeItem(offsets: offsets, model: parentModel)
        } else {
            for index in offsets {
                if items[index].id == listModel.selected {
                    listModel.update(selection: Set())
                }
                Task { @MainActor in
                    editController.delete(model: items[index])
                }
            }
        }
    }
    
    func moveItems(source: IndexSet, destination: Int) {
        guard let parentModel else { return }
        editController.moveItems(source: source, destination: destination, model: parentModel)
    }
    
    @ViewBuilder
    func listView() -> some View {
        @Bindable var listModel = listModel
#if os(macOS)
        if listDisplayModel.isSelectionMode {
            List(selection: $listModel.listSelection) {
                itemRows()
            }
        } else {
            List(selection: $listModel.selected) {
                itemRows()
            }
        }
#else
        List(selection: $listModel.listSelection) {
            itemRows()
        }
#endif
    }
    
    func itemRows() -> some View {
        ForEach(totalItems) { item in
            HStack {
                row(item.model.id)
                    .applyIf(!listDisplayModel.isSelectionMode) { content in
                        content.contextMenu {
                            ItemListContextMenu(controller: menuController, currentSelected: item.model.id)
                        }
                    }
                
                specialCategoryFolderIndicator(model: item.model)
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
        .moveDisabled(parentModel == nil || parentModel?.category == .folder)
        .deleteDisabled(listDisplayModel.isSelectionMode)
    }
    
    func addLinks(links: [LinkData]) {
        guard let parentModel else { return }
        links.forEach { link in
            guard link.module == EditController.Model.typeId else { return }
            withAnimation { editController.addItem(itemId: link.itemId, in: parentModel, folderId: listModel.lastFolderId) }
        }
    }
    
    var leadingPadding: CGFloat {
        let value = listDisplayModel.isSelectionMode ? 12 : 8
        return CGFloat(valueFor(iOS: value, macOS: 4, tvOS: value, visionOS: value))
    }
    
    @ViewBuilder
    func specialCategoryFolderIndicator(model: EditController.Model) -> some View {
        if model.category == .folder || model.category == EditController.Model.collectionCategory {
            Image(systemName: listModel.isFolderOpen(itemId: model.id) ? "chevron.down" : "chevron.right")
                .imageScale(.small)
                .padding(.trailing)
                .foregroundStyle(listModel.isFolderOpen(itemId: model.id) ? Color.accentColor : Color.secondary)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation { listModel.toggleFolder(itemId: model.id) }
                }
        }
    }
    
    var totalItems: [ItemListModel<EditController.Model>] {
        expandedItems(items: items)
    }

    func filteredItems(items: [EditController.Model], withParentFilter: Bool = true) -> [EditController.Model] {
        var filtered = items
        if withParentFilter {
            if parentModel == nil && listDisplayModel.listMode == .list {
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
    
    func expandedItems(items: [EditController.Model], level: Int = 0, withParentFilter: Bool = true, entryIds: [UUID: UUID] = [:]) -> [ItemListModel<EditController.Model>] {
        var total: [ItemListModel<EditController.Model>] = []
        guard level < 10 else { return total }
        let filtered = filteredItems(items: items, withParentFilter: withParentFilter)
        let sorted: [EditController.Model]
        if parentModel?.category == .folder {
            sorted = filtered.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        } else {
            sorted = filtered
        }
        sorted.forEach { item in
            total.append(ItemListModel(id: entryIds[item.id, default: item.id], model: item, isOpen: listModel.isFolderOpen(itemId: item.id), level: level))
            if item.specialCategory && listModel.isFolderOpen(itemId: item.id) {
                let (newItems, newEntryIds) = item.subItems
                total.append(contentsOf: expandedItems(items: newItems, level: level + 1, withParentFilter: false, entryIds: newEntryIds))
            }
        }
        if total.isEmpty && parentModel != nil {
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
