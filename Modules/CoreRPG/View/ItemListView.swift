// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct ItemListView<EditController: EditControllable, Row: View>: View where EditController.Model.ID == UUID {
    public init(editController: EditController, menuController: any ItemListContextMenuControllable, items: [EditController.Model], module: NetworkModules, route: @escaping (UUID) -> any NavigationDestination, @ViewBuilder row: @escaping (EditController.Model) -> Row) {
        self.editController = editController
        self.menuController = menuController
        self.items = items
        self.module = module
        self.route = route
        self.row = row
    }
    let editController: EditController
    let menuController: ItemListContextMenuControllable
    let items: [EditController.Model]
    let module: NetworkModules
    let route: (UUID) -> any NavigationDestination
    let row: (EditController.Model) -> Row
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.navigator) private var navigator
    
    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(ListModel.self) private var listModel
    @Environment(SearchModel.self) private var searchModel
    
#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var editMode: EditMode = .inactive
#endif
    
    public var body: some View {
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
            .navigationTitle(module.title)
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

private extension ItemListView {
    @ViewBuilder
    var actionMenu: some View {
        Menu {
            MenuDisplayModeToggle(listModel: listModel, showSelectionButton: false) {
                addItemButton(for: .folder)
                    .disabled(listModel.isListMode)
                addItemButton(for: .collection)
                    .disabled(listModel.isListMode)
                Divider()
            }
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
        .disabled(listModel.isListMode)
        
        ControlGroup {
            CompactDisplayModeToggle(listModel: listModel)
            MediumDisplayModeToggle(listModel: listModel)
            RegularDisplayModeToggle(listModel: listModel)
        }
        ControlGroup {
            ListModeToggle(listModel: listModel)
            FolderModeToggle(listModel: listModel)
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
            listModel.selected = newItem.id
        }
    }
    
    func deleteItems(offsets: IndexSet) {
        for index in offsets {
            if items[index].id == listModel.selected {
                listModel.update(selection: Set())
            }
            Task { @MainActor in
                editController.delete(model: items[index])
            }
        }
    }
    
    var filteredItems: [EditController.Model] {
        var filtered = items
        if listModel.listMode == .list {
            filtered = filtered.filter { $0.category != .folder && $0.category != EditController.Model.collectionCategory }
        } else {
            filtered = filtered.filter { $0.parentId == listModel.selectedParentId }
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
    func listView(filteredItems: [EditController.Model]) -> some View {
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
    
    func itemRows(filteredItems: [EditController.Model]) -> some View {
        ForEach(filteredItems) { item in
            row(item)
                .applyIf(!listModel.isSelectionMode) { content in
                    content.contextMenu {
                        ItemListContextMenu(controller: menuController, currentSelected: item.id)
                    }
                }
                .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
        }
        .onDelete(perform: deleteItems)
        .deleteDisabled(listModel.isSelectionMode)
    }
    
    var leadingPadding: CGFloat {
        let value = listModel.isSelectionMode ? 12 : 8
        return CGFloat(valueFor(iOS: value, macOS: 4, tvOS: value, visionOS: value))
    }
    
    func totalItems(items: [EditController.Model]) -> [EditController.Model] {
        var total: [EditController.Model] = []
        filteredItems.forEach { item in
            total.append(item)
            if item.isFolder && listModel.subItemModels[item.id]?.isOpen ?? false {
                total.append(contentsOf: totalItems(items: item.subItems))
            }
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
