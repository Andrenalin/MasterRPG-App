// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

public struct ItemListView<ListController: ListControllable, EditController: EditControllable, Row: View>: View where ListController.Model == EditController.Model, EditController.Model.ID == UUID {
    public init(listController: ListController, editController: EditController, menuController: any ItemListContextMenuControllable, parentModel: EditController.Model? = nil, module: NetworkModules, route: @escaping (UUID) -> any NavigationDestination, @ViewBuilder row: @escaping (UUID) -> Row) {
        self.listController = listController
        self.editController = editController
        self.menuController = menuController
        self.parentModel = parentModel
        self.module = module
        self.route = route
        self.row = row
    }
    let listController: ListController
    let editController: EditController
    let menuController: ItemListContextMenuControllable
    let parentModel: EditController.Model?
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
                if displayItems.isEmpty && !listController.searchModel.searchText.isEmpty {
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
            .animation(.smooth, value: displayItems.count)
#if os(iOS) || os(visionOS)
            .environment(\.editMode, $editMode)
#endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: displayItems.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
            .applyIf(parentModel == nil) {
                $0.navigationTitle(module.title)
            }
            .onAppear {
                withAnimation { listModel.resetListModel() }
            }
            .onChange(of: listController.listDisplayModel.isSelectionMode) {
                listModel.update(selectionMode: listController.listDisplayModel.isSelectionMode)
            }
            .onChange(of: listModel.listSelection) {
                updateListSelection()
            }
            .onChange(of: listModel.selected) {
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
    var displayItems: [ListItemModel] {
        listController.displayItems(for: parentModel)
    }

    var listModel: ListModel {
        listController.listModel(for: parentModel)
    }

    func updateListSelection() {
        listModel.update(selection: listModel.listSelection)
    }

    func updateSelected() {
        if let id = listModel.selected, let item = displayItems.first(where: { $0.id == id }) {

            if item.itemId == EditController.Model.dropItem.id {
                navigator.navigate(to: route(EditController.Model.dropItem.id), method: .sheet)
                listModel.update(selection: [])
            } else {
                listModel.listSelection <=> Set(arrayLiteral: id)
                navigator.navigate(to: route(item.itemId), method: .push)
            }
        } else {
            listModel.resetListSelection()
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
                editController.addItem(itemId: newModel.id, in: modelContext, parentId: listModel.selectedParentId, folderId:  listModel.lastFolderId)
            }
            listController.add(model: newModel)
        }
    }
    
    func deleteItems(offsets: IndexSet) {
        if let parentModel {
            editController.removeItem(offsets: offsets, model: parentModel)
        } else {
            for index in offsets {
                if displayItems[index].id == listModel.selected {
                    listModel.update(selection: Set())
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
        @Bindable var listModel = listModel
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
        ForEach(displayItems) { item in
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
            withAnimation { editController.addItem(itemId: link.itemId, in: parentModel, folderId: listModel.lastFolderId) }
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

    var secondaryMenuPlacement: ToolbarItemPlacement {
#if os(tvOS)
        .automatic
#else
        .secondaryAction
#endif
    }
}
