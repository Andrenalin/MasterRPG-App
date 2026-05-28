// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

struct ListRootView: View {
    let root: ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessable)?
    
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        listView
            .animation(.smooth, value: displayItems.count)
            .frame(minWidth: 250, idealWidth: 350)
#if !os(tvOS)
            .applyIf(listController.listDisplayModel.isSelectionMode) { content in
                content.contextMenu(forSelectionType: ListItemModel.ID.self) { selectedItemIDs in
                    ListRootContextMenu(root: root, controller: menuController, parentItem: parentModel, listController: listController)
                }
            }
#endif
            .applyIf(parentModel == nil) {
                $0.navigationTitle("\(root.configurable.module.title) - \(displayItems.count)")
            }
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: displayItems.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
#if os(macOS)
            .onDeleteCommand {
                guard let itemId = listModel.selectedItemId, let index = displayItems.firstIndex(where: { $0.model.id == itemId }) else { return }
                deleteItems(offsets: IndexSet(integer: index))
            }
            .onKeyPress(.leftArrow, phases: .down) { _ in
                withAnimation { listController.closeParentFolder() }
                return .handled
            }
            .onKeyPress(.rightArrow, phases: .down) { _ in
                withAnimation { listController.openSelectedFolder() }
                return .handled
            }
#endif
        
            .overlay {
                if displayItems.isEmpty && !listController.searchModel.searchText.isEmpty && !listController.searchModel.searchText.starts(with: "@") {
                    ContentUnavailableView.search
                }
            }
            .applyIf(parentModel == nil) {
                $0
                    .onChange(of: root.navigationModel.triggerExport) {
                        guard root.navigationModel.triggerExport, let itemId = root.currentSelectedItemId else { return }
                        root.navigationModel.triggerExport = false
                        navigator.navigate(to: InternalRoute.export(ids: [itemId]), method: .sheet)
                    }
                    .onChange(of: root.navigationModel.triggerGroupEditor) {
                        guard root.navigationModel.triggerGroupEditor, let itemId = root.currentSelectedItemId else { return }
                        root.navigationModel.triggerGroupEditor = false
                        navigator.navigate(to: InternalRoute.groupEditor(ids: [itemId]), method: .sheet)
                    }
                    .onChange(of: root.navigationModel.triggerSpaceAction) {
                        guard root.navigationModel.triggerSpaceAction else { return }
                        root.navigationModel.triggerSpaceAction = false
                        guard !root.viewControllable.hasCustomSpaceAction,
                              root.openFileWindowModel.enabled else { return }
                        withAnimation { root.openFileWindowModel.showItem.toggle() }
                    }
            }
            .listModelUpdatesModifier(listControllable: listController, itemControllable: root.itemControllable)
            .toolbarItemListModifier(root: root, listControllable: listController, parentModel: parentModel)
#if !os(tvOS)
            .applyIf(!fileTypes.isEmpty) {
                $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: updateFile))
            }
#endif
    }
}

private extension ListRootView {
    var displayItems: [ListItemModel] {
        parentModel == nil ? listController.listModel.displayedItems : listController.listModel.displayedParentItems
    }
    
    var listModel: FolderListModel {
        listController.listModel
    }
    
    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    var menuController: ContextMenuMultiController {
        ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: listModel)
    }
    
    func updateFile(url: URL) {
        Task {
            guard let model = await root.editControllable.addNew(type: .item) else { return }
            await root.editControllable.resetFile(url: url, itemId: model.id)
            let cc = ConvertController(itemController: root.itemControllable, editController: root.editControllable)
            await cc.moveAndCreateFolders(itemId: model.id)
            try? await Task.sleep(for: .seconds(0.2))
            if parentModel != nil {
                root.editControllable.addItem(itemId: model.id, parentId: listModel.selectedParentId)
                // Reset parent list filter when adding to folder/collection
                root.folderListControllable.resetFilter()
            }
            guard let updatedModel = root.itemControllable.itemSync(for: model.id) else { return }
            withAnimation {
                listController.add(model: updatedModel)
                listController.resetFilter()
                listController.listModel.set(selectedItemId: updatedModel.id)
                listController.listModel.scrollId = listController.listModel.selected
            }
        }
    }
    
    @ViewBuilder
    var listView: some View {
        ScrollViewReader { proxy in
            Group {
                @Bindable var listModel = listModel
#if os(macOS)
                Group {
                    if listController.listDisplayModel.isSelectionMode {
                        List(selection: $listModel.listSelection) {
                            itemRows()
                        }
                        .frame(minHeight: 300, maxHeight: .infinity)
                    } else {
                        List(selection: $listModel.selected) {
                            itemRows()
                        }
                        .frame(minHeight: 300, maxHeight: .infinity)
                    }
                }
                .applyIf(parentModel != nil) {
                    $0.listStyle(.bordered)
                }
                .applyIf(parentModel != nil) {
                    $0.listStyle(.sidebar)
                }
#else
                List(selection: $listModel.listSelection) {
                    itemRows()
                }
#endif
            }
            .onChange(of: listModel.scrollId) {
                guard let id = listModel.scrollId else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
    
    @ViewBuilder func itemRows() -> some View {
        if displayItems.isEmpty && parentModel != nil {

            VStack(spacing: 0) {
                Text("Drop here", bundle: .module)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(root.configurable.module.color.gradient, in: .capsule)
                    .padding()
                    .dropDestination(for: root.configurable.module, isEnabled: parentModel != nil, handler: addLink(name:itemId:entryId:))
            
                Text("Drag items from the list or the inspector on this drop field to add the item to the folder or collection. After the first item is added you can add more items by dropping it on the exisiting items in this detail list.")
                    .padding()
                    .lineLimit(5)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        
        ForEach(displayItems) { item in
            HStack {
                ItemRowView(root: root, model: item.model, cacheItemListModel: listController.cacheListItemModel, listDisplayModel: listController.listDisplayModel, searchModel: listController.searchModel, isSelected: false) {
                    if root.viewControllable.thumbnailRowViewType == .custom {
                        root.viewControllable.thumbnailRowView(for: item.model.id)
                    } else if root.viewControllable.thumbnailRowViewType == .photo, let cacheController = root.cacheControllable {
                        ThumbnailRowPhotoView(cacheController: cacheController, model: item.model, listDisplayModel: listController.listDisplayModel)
                    }
                }
                .draggable(for: root.configurable.module, itemId: item.model.id, entryId: nil, name: item.model.name)
                .applyIf(!listController.listDisplayModel.isSelectionMode) { content in
                    content.contextMenu {
                        ListRootContextMenu(root: root, controller: menuController, parentItem: parentModel, currentSelected: item.model.id, listController: listController)
                    }
                }
                
                specialCategoryFolderIndicator(item: item)
            }
            .environment(listController.listDisplayModel)
            .padding(.leading, CGFloat(item.level * 16))
            .dropDestination(for: root.configurable.module, isEnabled: parentModel != nil, handler: addLink(name:itemId:entryId:))
            .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
            .listRowSeparatorAll(item.isOpen ? .visible : .hidden, edges: .bottom)
        }
        .onDelete(perform: deleteItems)
        .onMove(perform: moveItems)
        .moveDisabled(parentModel == nil || parentModel?.category == .folder)
        .deleteDisabled(listController.listDisplayModel.isSelectionMode)
    }
    
    func addLink(name: String, itemId: UUID, entryId: UUID?) {
        guard let parentModel else { return }
        withAnimation {
            root.editControllable.addItem(itemId: itemId, parentId: parentModel.id)
            // Refresh the detail list from the updated parent model entries
            listController.update()
            // Also refresh the parent folder list
            root.folderListControllable.resetFilter()
        }
    }
    
    func deleteItems(offsets: IndexSet) {
        if let parentModel {
            root.editControllable.removeItem(offsets: offsets, itemId: parentModel.id)
            listModel.deleteItems(offsets: offsets)
        } else {
            let removingItems = listController.delete(offsets: offsets)
            guard !removingItems.isEmpty else { return }
            
            root.removeEntryListModel.removeItems = root.editControllable.markCollectionItemsForRemoval(for: removingItems)
            
            navigator.navigate(to: InternalRoute.removeAlert, method: .managedSheet)
        }
    }
    
    func moveItems(source: IndexSet, destination: Int) {
        guard let parentModel else { return }
        root.editControllable.moveItems(source: source, destination: destination, itemId: parentModel.id)
    }
    
    var leadingPadding: CGFloat {
        let value = listController.listDisplayModel.isSelectionMode ? 12 : 8
        return CGFloat(valueFor(iOS: value, macOS: 4, tvOS: value, visionOS: value))
    }
    
    @ViewBuilder
    func specialCategoryFolderIndicator(item: ListItemModel) -> some View {
        if item.model.specialCategory {
            Button {
                withAnimation { listController.toggleFolder(item: item) }
            } label: {
                Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                    .imageScale(.small)
                    .padding(.trailing)
                    .foregroundStyle(item.isOpen ? Color.accentColor : Color.secondary)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

}

//#Preview("Split", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//
//    ListRootView(root: root, parentModel: nil)
//}
