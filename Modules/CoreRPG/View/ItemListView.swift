// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct ItemListView<ListController: ListControllable, EditController: EditControllable, Row: View>: View where ListController.Model == EditController.Model, EditController.Model.ID == UUID {
    public init(listController: ListController, editController: EditController, menuController: any ItemListContextMenuControllable, parentModel: EditController.Model? = nil, items: [EditController.Model], module: NetworkModules, route: @escaping (UUID) -> any NavigationDestination, @ViewBuilder row: @escaping (UUID) -> Row) {
        self.listController = listController
        self.editController = editController
        self.menuController = menuController
        self.parentModel = parentModel
        self.items = items
        self.module = module
        self.route = route
        self.row = row
    }
    let listController: ListController
    let editController: EditController
    let menuController: ItemListContextMenuControllable
    let parentModel: EditController.Model?
    let items: [EditController.Model]
    let module: NetworkModules
    let route: (UUID) -> any NavigationDestination
    let row: (UUID) -> Row
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel

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
                if listController.listModel.displayedItems.isEmpty && !listController.searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
#if !os(tvOS)
            .applyIf(listController.listDisplayModel.isSelectionMode) { content in
                content.contextMenu(forSelectionType: EditController.Model.ID.self) { selectedItemIDs in
                    ItemListContextMenu(controller: menuController)
                }
            }
#endif
            .animation(.smooth, value: listController.listModel.displayedItems.count)
#if os(iOS) || os(visionOS)
            .environment(\.editMode, $editMode)
#endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: listController.listModel.displayedItems.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
            .applyIf(parentModel == nil) {
                $0.navigationTitle(module.title)
            }
            .onAppear {
                withAnimation { listController.listModel.resetListModel() }
            }
            .onChange(of: listController.listDisplayModel.isSelectionMode) {
                listController.listModel.update(selectionMode: listController.listDisplayModel.isSelectionMode)
            }
            .onChange(of: listController.listModel.listSelection) {
                updateListSelection()
            }
            .onChange(of: listController.listModel.selected) {
                updateSelected()
            }
            .onChange(of: listController.listDisplayModel.listMode) {
                withAnimation { listController.resetFilter() }
            }
#if os(iOS) || os(visionOS)
            .onChange(of: listController.listDisplayModel.isSelectionMode) {
                editMode = listController.listDisplayModel.isSelectionMode ? .active : .inactive
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
                if listController.listDisplayModel.isSelectionMode {
                    ToolbarItem(placement: .primaryAction) {
                        MenuSelectionButtonView(listDisplayModel: listController.listDisplayModel)
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
    func updateListSelection() {
        listController.listModel.update(selection: listController.listModel.listSelection)
    }

    func updateSelected() {
        if let id = listController.listModel.selected, let item = listController.listModel.displayedItems.first(where: { $0.id == id }) {

            if item.itemId == EditController.Model.dropItem.id {
                navigator.navigate(to: route(EditController.Model.dropItem.id), method: .sheet)
                listController.listModel.update(selection: [])
            } else {
                listController.listModel.listSelection <=> Set(arrayLiteral: id)
                navigator.navigate(to: route(item.itemId), method: .push)
            }
        } else {
            listController.listModel.resetListSelection()
        }
    }

    @ViewBuilder
    var actionMenu: some View {
        Menu {
            MenuDisplayModeToggle(listDisplayModel: listController.listDisplayModel, showSelectionButton: false) {
                if parentModel == nil {
                    addItemButton(for: .folder)
                        .disabled(listController.listDisplayModel.isListMode)
                    addItemButton(for: .collection)
                        .disabled(listController.listDisplayModel.isListMode)
                    Divider()
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    @ViewBuilder
    var secondaryActionMenu: some View {
        if !listController.listDisplayModel.isSelectionMode {
            MenuSelectionButtonView(listDisplayModel: listController.listDisplayModel)
        }
        ControlGroup {
            addItemButton(for: .folder)
            addItemButton(for: .collection)
        }
        .disabled(listController.listDisplayModel.isListMode)

        ControlGroup {
            CompactDisplayModeToggle(listDisplayModel: listController.listDisplayModel)
            MediumDisplayModeToggle(listDisplayModel: listController.listDisplayModel)
            RegularDisplayModeToggle(listDisplayModel: listController.listDisplayModel)
        }
        if parentModel == nil {
            ControlGroup {
                ListModeToggle(listDisplayModel: listController.listDisplayModel)
                FolderModeToggle(listDisplayModel: listController.listDisplayModel)
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
        let newModel = editController.addNew(modelContext: modelContext, type: type)
        withAnimation {
            if parentModel != nil {
                editController.addItem(itemId: newModel.id, in: modelContext, parentId: listController.listModel.selectedParentId, folderId:  listController.listModel.lastFolderId)
            }
            listController.add(model: newModel)
        }
    }
    
    func deleteItems(offsets: IndexSet) {
        if let parentModel {
            editController.removeItem(offsets: offsets, model: parentModel)
        } else {
            for index in offsets {
                if listController.listModel.displayedItems[index].id == listController.listModel.selected {
                    listController.listModel.update(selection: Set())
                }
                Task { @MainActor in
                    //editController.delete(model: listController.listModel.displayedItems[index].itemId)
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
        @Bindable var listModel = listController.listModel
#if os(macOS)
        if listController.listDisplayModel.isSelectionMode {
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
        ForEach(listController.listModel.displayedItems) { item in
            HStack {
                row(item.itemId)
                    .applyIf(!listController.listDisplayModel.isSelectionMode) { content in
                        content.contextMenu {
                            ItemListContextMenu(controller: menuController, currentSelected: item.itemId)
                        }
                    }
                
                specialCategoryFolderIndicator(item: item)
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
        .deleteDisabled(listController.listDisplayModel.isSelectionMode)
    }
    
    func addLinks(links: [LinkData]) {
        guard let parentModel else { return }
        links.forEach { link in
            guard link.module == EditController.Model.typeId else { return }
            withAnimation { editController.addItem(itemId: link.itemId, in: parentModel, folderId: listController.listModel.lastFolderId) }
        }
    }
    
    var leadingPadding: CGFloat {
        let value = listController.listDisplayModel.isSelectionMode ? 12 : 8
        return CGFloat(valueFor(iOS: value, macOS: 4, tvOS: value, visionOS: value))
    }
    
    @ViewBuilder
    func specialCategoryFolderIndicator(item: ListItemModel) -> some View {
        if item.isSpecial {
            Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                .imageScale(.small)
                .padding(.trailing)
                .foregroundStyle(item.isOpen ? Color.accentColor : Color.secondary)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation { listController.toggleFolder(item: item) }
                }
        }
    }
    
//    var totalItems: [ItemListModel<EditController.Model>] {
//        expandedItems(items: items)
//    }
//
//    func filteredItems(items: [EditController.Model], withParentFilter: Bool = true) -> [EditController.Model] {
//        var filtered = items
//        if withParentFilter {
//            if parentModel == nil && listController.listDisplayModel.listMode == .list {
//                filtered = filtered.filter { $0.category != .folder && $0.category != EditController.Model.collectionCategory }
//            } else {
//                filtered = filtered.filter { $0.parentId == listController.listModel.selectedParentId }
//            }
//        }
//        if !listController.searchModel.selectedTokens.isEmpty {
//            let selectedTags = listController.searchModel.selectedTokens.map { $0.tag }
//            filtered = filtered.filter { $0.tags.contains(selectedTags) }
//        }
//        guard !listController.searchModel.searchText.isEmpty else { return filtered }
//        return filtered.filter {
//            $0.name.localizedStandardContains(listController.searchModel.searchText) ||
//            $0.information.localizedStandardContains(listController.searchModel.searchText)
//        }
//    }
//    
//    func expandedItems(items: [EditController.Model], level: Int = 0, withParentFilter: Bool = true, entryIds: [UUID: UUID] = [:]) -> [ItemListModel<EditController.Model>] {
//        var total: [ItemListModel<EditController.Model>] = []
//        guard level < 10 else { return total }
//        let filtered = filteredItems(items: items, withParentFilter: withParentFilter)
//        let sorted: [EditController.Model]
//        if parentModel?.category == .folder {
//            sorted = filtered.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
//        } else {
//            sorted = filtered
//        }
//        sorted.forEach { item in
//            total.append(ItemListModel(id: entryIds[item.id, default: item.id], model: item, isOpen: listController.listModel.isFolderOpen(itemId: item.id), level: level))
//            if item.specialCategory && listController.listModel.isFolderOpen(itemId: item.id) {
//                let (newItems, newEntryIds) = item.subItems
//                total.append(contentsOf: expandedItems(items: newItems, level: level + 1, withParentFilter: false, entryIds: newEntryIds))
//            }
//        }
//        if total.isEmpty && parentModel != nil {
//            total.append(ItemListModel(id: EditController.Model.dropItem.id, model: EditController.Model.dropItem, isOpen: false, level: level))
//        }
//        return total
//    }

    var secondaryMenuPlacement: ToolbarItemPlacement {
#if os(tvOS)
        .automatic
#else
        .secondaryAction
#endif
    }
}
