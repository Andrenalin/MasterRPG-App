// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

struct ListRootView: View {
    let root: ItemRootControllable
    let listController: any FolderListControllable
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
            .onMoveCommand { direction in
                //selectItem(direction)
            }
#endif

            .overlay {
                if displayItems.isEmpty && !listController.searchModel.searchText.isEmpty {
                    ContentUnavailableView.search
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
        listController.displayItems
    }

    var listModel: FolderListModel {
        listController.listModel
    }
    
    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    var menuController: any ItemListContextMenuControllable {
        ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: listModel)
    }

    func updateFile(url: URL) {
        Task { @MainActor in
            guard let model = await root.editControllable.addNew(type: .item) else { return }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation {
                root.editControllable.resetFile(url: url, module: root.configurable.module)
                if parentModel != nil {
                    root.editControllable.addItem(itemId: model.id, parentId: listModel.selectedParentId)
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
            Text("Drop here")
                .dropDestination(for: root.configurable.module, isEnabled: parentModel != nil, handler: addLink(name:itemId:entryId:))
        }
        
        ForEach(displayItems) { item in
            HStack {
                ItemRowView(root: root, model: item.model, cacheItemListModel: listController.cacheListItemModel, isSelected: false) {
                    if root.viewControllable.thumbnailRowViewType == .custom {
                        root.viewControllable.thumbnailRowView(for: item.model.id)
                    } else if root.viewControllable.thumbnailRowViewType == .photo, let cacheController = root.cacheControllable {
                        ThumbnailRowPhotoView(cacheController: cacheController, model: item.model)
                    }
                }
                .draggable(for: root.configurable.module, itemId: item.model.id, entryId: nil, name: item.model.name)
                .applyIf(!listController.listDisplayModel.isSelectionMode) { content in
                    content.contextMenu {
                        ListRootContextMenu(controller: menuController, currentSelected: item.model.id)
                    }
                }

                specialCategoryFolderIndicator(item: item)
            }
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
        withAnimation { root.editControllable.addItem(itemId: itemId, parentId: parentModel.id) }
    }
    
    func deleteItems(offsets: IndexSet) {
        if let parentModel {
            root.editControllable.removeItem(offsets: offsets, item: parentModel)
            listModel.deleteItems(offsets: offsets)
        } else {
            let removingItems = listController.delete(offsets: offsets)
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
                    withAnimation { listController.toggleFolder(item: item) }
                }
        }
    }
}

//#Preview("Split", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//    
//    ListRootView(root: root, parentModel: nil)
//}
