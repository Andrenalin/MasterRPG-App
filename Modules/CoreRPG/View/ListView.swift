// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct ListView<Model: Identifiable, EditController: EditControllable, Row: View>: View where Model.ID == UUID, Model == EditController.Model {
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
    
    @State private var isCompactMode: Bool = false
    
    public var body: some View {
        listView(filteredItems: items)
            .frame(minWidth: 250, idealWidth: 350, maxWidth: 450)
            .overlay {
                if items.isEmpty && !searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .applyIf(listModel.isSelectionMode) { content in
                content.contextMenu(forSelectionType: Model.ID.self) { selectedItemIDs in
                    ItemListContextMenu(controller: menuController)
                }
            }
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
                ToolbarItemGroup(placement: .secondaryAction) {
                    if !listModel.isSelectionMode {
                        MenuSelectionButtonView(listModel: listModel)
                    }
                    ControlGroup {
                        addItemButton(asFolder: true)
                    }
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
#endif
                
                if listModel.isSelectionMode {
                    ToolbarItem(placement: .primaryAction) {
                        MenuSelectionButtonView(listModel: listModel)
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        addItemButton(asFolder: false)
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
    
    private func addItemButton(asFolder: Bool = false) -> some View {
        Button {
            addItem(asFolder)
        } label: {
            Label {
                Text("Add\(asFolder ? " folder" : "")", bundle: .module)
            } icon: {
                Image(systemName: asFolder ? "folder.badge.plus" : "plus")
            }
        }
    }
    
    private func addItem(_ asFolder: Bool) {
        let newItem = editController.addNew(modelContext: modelContext, listMode: asFolder ? .folder : .list)
        withAnimation {
            listModel.selected = newItem.id
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
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
}
