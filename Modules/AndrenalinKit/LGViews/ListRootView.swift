// @copyright André Trettin

import CoreExternalRPG
import SwiftUI
import UniformTypeIdentifiers

struct ListRootView: View {
    let root: ItemRootControllable
    let parentModel: (any ItemDataAccessable)?

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
                    ListRootContextMenu(controller: menuController)
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
                guard let itemId = listModel.selectedItemId, let index = displayItems.firstIndex(where: { $0.model.id == itemId }) else { return }
                deleteItems(offsets: IndexSet(integer: index))
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
            .onChange(of: root.itemControllable.itemDataModel.items, initial: true) {
                withAnimation {
                    let items = root.itemControllable.itemDataModel.items.map { root.itemControllable.itemOrEmpty(for: $0) }
                    listController.update(items: items, parentModel: parentModel)
                }
            }
            .listModelUpdatesModifier(listControllable: listController, parentModel: parentModel)
            .toolbarItemListModifier(root: root, listControllable: listController, parentModel: parentModel)
#if !os(tvOS)
            .applyIf(!fileTypes.isEmpty) {
                $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: updateFile))
            }
#endif
    }
}

private extension ListRootView {
    var listController: any FolderListControllable {
        root.folderListControllable
    }

    var displayItems: [ListItemModel] {
        listController.displayItems(for: parentModel)
    }

    var listModel: FolderListModel {
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
//            let modelContext = root.itemControllable.container.mainContext
//            let model = root.editControllable.addNew(modelContext: modelContext, module: root.module, type: .item)
//            try? await Task.sleep(for: .seconds(0.5))
//            withAnimation {
//                root.editControllable.resetFile(url: url, in: model)
//                if parentModel != nil {
//                    root.editControllable.addItem(itemId: model.id, in: modelContext, parentId: listModel.selectedParentId, folderId:  listModel.lastFolderId)
//                }
//                listController.add(model: model)
//            }
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
                ItemRowView(root: root, model: item.model, cacheItemListModel: listController.cacheListItemModel, isSelected: false) {
                    if root.viewControllable.thumbnailRowViewType == .custom {
                        root.viewControllable.thumbnailRowView(for: item.model.id)
                    } else if root.viewControllable.thumbnailRowViewType == .photo, let cacheController = root.cacheControllable {
                        ThumbnailRowPhotoView(cacheController: cacheController, model: item.model)
                    }
                }
                .draggable(for: root.module, itemId: item.model.id, entryId: nil, name: item.model.name)
                .applyIf(!listController.listDisplayModel.isSelectionMode) { content in
                    content.contextMenu {
                        ListRootContextMenu(controller: menuController, currentSelected: item.model.id)
                    }
                }

                specialCategoryFolderIndicator(item: item)
            }
            .padding(.leading, CGFloat(item.level * 16))
            .dropDestination(for: root.module, isEnabled: parentModel != nil, handler: addLink(name:itemId:entryId:))
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
//        withAnimation { root.editControllable.addItem(itemId: itemId, in: parentModel, folderId: listModel.lastFolderId) }
    }
    
    func deleteItems(offsets: IndexSet) {
        if let parentModel {
            root.editControllable.removeItem(offsets: offsets, item: parentModel)
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
        root.editControllable.moveItems(source: source, destination: destination, item: parentModel)
    }

    var leadingPadding: CGFloat {
        let value = listController.listDisplayModel.isSelectionMode ? 12 : 8
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
                    withAnimation { listController.toggleFolder(item: item, parentModel: parentModel) }
                }
        }
    }
}

//#Preview("Split", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    
//    ListRootView(root: root, parentModel: nil)
//}
