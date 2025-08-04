// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public protocol ListItemFolderable: Identifiable {
    var isFolder: Bool { get }
    @MainActor var subItems: [Self] { get }
    
    @MainActor static var dropItem: Self { get }
    @MainActor static var collectionCategory: ItemListCategory { get }
}

public struct ListView<Model: ListItemFolderable, EditController: EditControllable, Row: View>: View where Model.ID == UUID, Model == EditController.Model {
    public init(editController: EditController, menuController: any ItemListContextMenuControllable, items: [Model], module: NetworkModules, route: @escaping (UUID) -> any NavigationDestination, row: @escaping (Model) -> Row) {
        self.editController = editController
        self.menuController = menuController
        self.items = items
        self.module = module
        self.route = route
        self.row = row
    }
    let editController: EditController
    let menuController: ItemListContextMenuControllable
    let items: [Model]
    let module: NetworkModules
    let route: (UUID) -> any NavigationDestination
    let row: (Model) -> Row
    
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
            .frame(minWidth: 250, idealWidth: 350, maxWidth: 450)
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
    
    @ViewBuilder
    private var actionMenu: some View {
        Menu {
            MenuDisplayModeToggle(listModel: listModel, showSelectionButton: false)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
    
    @ViewBuilder
    private var secondaryActionMenu: some View {
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
    
    private func addItemButton(for type: EditControllerAddType) -> some View {
        Button {
            addItem(for: type)
        } label: {
            Label {
                Text(type.title)
            } icon: {
                Image(systemName: type.icon(collection: Model.collectionCategory.icon))
            }
        }
    }
    
    private func addItem(for type: EditControllerAddType) {
        let newItem = editController.addNew(modelContext: modelContext, type: type)
        withAnimation {
            listModel.selected = newItem.id
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            if items[index].id == listModel.selected {
                listModel.update(selection: Set())
            }
            Task { @MainActor in
                editController.delete(model: items[index])
            }
        }
    }
    
    @ViewBuilder
    private func listView(filteredItems: [Model]) -> some View {
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
    
    private func itemRows(filteredItems: [Model]) -> some View {
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
    
    func totalItems(items: [Model]) -> [Model] {
        var total: [Model] = []
        items.forEach { item in
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
