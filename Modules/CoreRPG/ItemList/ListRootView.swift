// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ListRootView: View {
    let root: ItemRootControllable
    let parentModel: ItemDataModel?

    @Environment(CacheItemListModel.self) private var cacheItemListModel
    @Environment(\.navigator) private var navigator

    var body: some View {
        let _ = Self._printChanges()
        let _ = print(parentModel?.name ?? "No parent")
        
        listView
            .animation(.smooth, value: displayItems.count)
            .frame(minWidth: 250, idealWidth: 350)
#if !os(tvOS)
            .applyIf(listController.listDisplayModel.isSelectionMode) { content in
                content.contextMenu(forSelectionType: ListItemModel.ID.self) { selectedItemIDs in
                    ItemListContextMenu(controller: menuController)
                }
            }
#endif
            .applyIf(parentModel == nil) {
                $0.navigationTitle(root.module.title)
            }
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: displayItems.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
#if os(macOS)
            .onDeleteCommand {
                guard let itemId = listModel.selectedItemId else { return }
                removeEntryList.removeItems = [ItemRowModel(itemId: itemId, typeId: root.module)]
                withAnimation { removeEntryList.showDeleteAlert.toggle() }
            }
            .onMoveCommand { direction in
                //selectItem(direction)
            }
#endif

            .overlay {
                if displayItems.isEmpty && !listController.searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .onChange(of: root.itemControllable.itemCacheModel.itemIds, initial: true) {
                withAnimation { root.listControllable.update(items: root.itemControllable.allItems(), parentModel: parentModel) }
            }
            .listModelUpdatesModifier(listControllable: root.listControllable, parentModel: parentModel)
            .toolbarItemListModifier(root: root, listControllable: root.listControllable, parentModel: parentModel)
#if !os(tvOS)
            .applyIf(!fileTypes.isEmpty) {
                $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: updateFile))
            }
#endif
    }
}

private extension ListRootView {
    var listController: any ListControllable {
        root.listControllable
    }

    var displayItems: [ListItemModel] {
        listController.displayItems(for: parentModel)
    }

    var listModel: ListModel {
        listController.listModel(for: parentModel)
    }
    
    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: listModel)
    }

    func updateFile(url: URL) {
        Task { @MainActor in
            let modelContext = root.itemControllable.container.mainContext
            let model = root.editControllable.addNew(modelContext: modelContext, module: root.module, type: .item)
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation {
                root.editControllable.resetFile(url: url, in: model)
                if parentModel != nil {
                    root.editControllable.addItem(itemId: model.id, in: modelContext, parentId: listModel.selectedParentId, folderId:  listModel.lastFolderId)
                }
                listController.add(model: model)
            }
        }
    }

    @ViewBuilder
    var listView: some View {
        ScrollViewReader { proxy in
            Group {
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
            .onChange(of: listModel.scrollId) {
                guard let id = listModel.scrollId else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    func itemRows() -> some View {
        ForEach(displayItems) { item in
            HStack {
                ItemRowView(root: root, model: item.model, cacheItemListModel: cacheItemListModel, isSelected: false) {
                    if root.viewControllable.thumbnailRowViewType == .custom {
                        root.viewControllable.thumbnailRowView(for: item.model.id)
                    } else if root.viewControllable.thumbnailRowViewType == .photo, let cacheController = root.cacheControllable {
                        ThumbnailRowPhotoView(cacheController: cacheController, model: item.model)
                    }
                }
#if !os(tvOS)
                .draggable(LinkData(itemId: item.model.id, module: root.module, name: item.model.name))
#endif
                .applyIf(!listController.listDisplayModel.isSelectionMode) { content in
                    content.contextMenu {
                        ItemListContextMenu(controller: menuController, currentSelected: item.model.id)
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
        .deleteDisabled(root.listControllable.listDisplayModel.isSelectionMode)
    }

    func addLinks(links: [LinkData]) {
        guard let parentModel else { return }
        links.forEach { link in
            guard link.module == root.module else { return }
            withAnimation { root.editControllable.addItem(itemId: link.itemId, in: parentModel, folderId: listModel.lastFolderId) }
        }
    }
    
    func deleteItems(offsets: IndexSet) {
        if let parentModel {
            root.editControllable.removeItem(offsets: offsets, model: parentModel)
            listModel.deleteItems(offsets: offsets)
        } else {
            let removingItems = listController.delete(offsets: offsets, parentModel: parentModel)
            guard !removingItems.isEmpty else { return }
            root.removeEntryListModel.removeItems = removingItems
            removingItems.forEach {
                root.editControllable.markForDeletion(itemId: $0.itemId)
            }
            navigator.navigate(to: InternalRoute.removeAlert, method: .managedSheet)
        }
    }
    
    func moveItems(source: IndexSet, destination: Int) {
        guard let parentModel else { return }
        root.editControllable.moveItems(source: source, destination: destination, model: parentModel)
    }

    var leadingPadding: CGFloat {
        let value = root.listControllable.listDisplayModel.isSelectionMode ? 12 : 8
        return CGFloat(valueFor(iOS: value, macOS: 4, tvOS: value, visionOS: value))
    }

    @ViewBuilder
    func specialCategoryFolderIndicator(item: ListItemModel) -> some View {
        if item.model.specialCategory {
            Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                .imageScale(.small)
                .padding(.trailing)
                .foregroundStyle(item.isOpen ? Color.accentColor : Color.secondary)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation { root.listControllable.toggleFolder(item: item, parentModel: parentModel) }
                }
        }
    }
}

//#Preview("Split", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    
//    ListRootView(root: root, parentModel: nil)
//}
