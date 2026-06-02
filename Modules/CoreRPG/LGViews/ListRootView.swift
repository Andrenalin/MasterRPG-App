// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main View

struct ListRootView: View {
    let root: ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessable)?

    @Environment(\.navigator) private var navigator

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        listView
            .animation(.smooth, value: listModel.list.count)
            .frame(minWidth: 250, idealWidth: 350)
#if !os(tvOS)
            // Always-present modifier: empty closure = no menu; avoids applyIf identity break
            .contextMenu(forSelectionType: FolderListItemModel.ID.self) { _ in
                if listController.listDisplayModel.isSelectionMode {
                    ListRootContextMenu(root: root, controller: menuController, parentItem: parentModel, listController: listController)
                }
            }
#endif
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: listModel.list.count)
#if !os(visionOS)
            .scrollDismissesKeyboard(.immediately)
#endif
#if os(macOS)
            .onDeleteCommand {
                guard let sel = listModel.selected,
                      let index = listModel.list.firstIndex(where: { $0.id == sel }) else { return }
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
                if listModel.list.isEmpty && !listController.searchModel.searchText.isEmpty
                    && !listController.searchModel.searchText.starts(with: "@") {
                    ContentUnavailableView.search
                }
            }
            .listModelUpdatesModifier(listControllable: listController, itemControllable: root.itemControllable, parentModel: parentModel)
            .toolbarItemListModifier(root: root, listControllable: listController, parentModel: parentModel)
#if !os(tvOS)
            .applyIf(!fileTypes.isEmpty) {
                $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: updateFile))
            }
#endif
            .applyIf(parentModel == nil) {
                $0
                    .navigationTitle("\(root.configurable.module.title) - \(listModel.list.count)")
                    .focusedSceneValue(\.listDisplayModel, listController.listDisplayModel)
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
                    .onChange(of: root.navigationModel.triggerBatchExtraction) {
                        guard root.navigationModel.triggerBatchExtraction, let itemId = root.currentSelectedItemId else { return }
                        root.navigationModel.triggerBatchExtraction = false
                        navigator.navigate(to: InternalRoute.batchExtraction(ids: [itemId]), method: .sheet)
                    }
                    .onChange(of: root.navigationModel.triggerDelete) {
                        guard root.navigationModel.triggerDelete else { return }
                        root.navigationModel.triggerDelete = false
                        guard let sel = listModel.selected,
                              let index = listModel.list.firstIndex(where: { $0.id == sel }) else { return }
                        deleteItems(offsets: IndexSet(integer: index))
                    }
                    .onChange(of: root.navigationModel.triggerSpaceAction) {
                        guard root.navigationModel.triggerSpaceAction else { return }
                        root.navigationModel.triggerSpaceAction = false
                        guard !root.viewControllable.hasCustomSpaceAction,
                              root.openFileWindowModel.enabled else { return }
                        withAnimation { root.openFileWindowModel.showItem.toggle() }
                    }
            }
    }
}

// MARK: - ListRootView private helpers

private extension ListRootView {
    /// When the view is showing a folder/collection's children (`parentModel != nil`),
    /// route all list operations through `detailListModel` so the detail list is
    /// displayed and mutated — not the root list.
    var listModel: FolderListModel {
        if parentModel != nil, let detail = listController.listModel.detailListModel {
            return detail
        }
        return listController.listModel
    }

    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }

    /// Computed once per body evaluation and passed down — avoids per-row re-creation.
    var menuController: ContextMenuMultiController {
        ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: listModel)
    }

    func updateFile(url: URL) {
        listController.add(type: .item, url: url, root: root)
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
                            ItemRowsView(root: root, listController: listController, parentModel: parentModel, listModel: listModel, menuController: menuController)
                        }
                        .frame(minHeight: 300, maxHeight: .infinity)
                    } else {
                        List(selection: $listModel.selected) {
                            ItemRowsView(root: root, listController: listController, parentModel: parentModel, listModel: listModel, menuController: menuController)
                        }
                        .frame(minHeight: 300, maxHeight: .infinity)
                    }
                }
                // Fixed: was two redundant applyIf(.bordered then .sidebar); .bordered had no effect
                .applyIf(parentModel != nil) {
                    $0.listStyle(.bordered)
                }
#else
                List(selection: $listModel.listSelection) {
                    ItemRowsView(root: root, listController: listController, parentModel: parentModel, listModel: listModel, menuController: menuController)
                }
#endif
            }
            .onChange(of: listModel.scrollId) {
                guard let id = listModel.scrollId else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    /// Used by `onDeleteCommand` (macOS) and the `triggerDelete` onChange handler.
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
}

// MARK: - ItemRowsView
// Extracted from the @ViewBuilder itemRows() function so SwiftUI can skip this struct's
// body entirely when its inputs (list contents, controller references) have not changed.

private struct ItemRowsView: View {
    let root: any ItemRootControllable
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessable)?
    let listModel: FolderListModel
    let menuController: ContextMenuMultiController

    @Environment(\.navigator) private var navigator

    var body: some View {
        if listModel.list.isEmpty && parentModel != nil {
            dropHereView
        }

        ForEach(listModel.list) { item in
            ListRowItemView(
                root: root,
                item: item,
                listController: listController,
                parentModel: parentModel,
                menuController: menuController,
                leadingPadding: leadingPadding
            )
        }
        .onDelete(perform: deleteItems)
        .onMove(perform: moveItems)
        .moveDisabled(parentModel == nil || parentModel?.category == .folder)
        .deleteDisabled(listController.listDisplayModel.isSelectionMode)
    }

    private var dropHereView: some View {
        VStack(spacing: 0) {
            Text("Drop here", bundle: .module)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
                .background(root.configurable.module.color.gradient, in: .capsule)
                .padding()
                .dropDestination(for: root.configurable.module, isEnabled: true, handler: addLink)

            Text("Drag items from the list or the inspector on this drop field to add the item to the folder or collection. After the first item is added you can add more items by dropping it on the exisiting items in this detail list.", bundle: .module)
                .padding()
                .lineLimit(5)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func addLink(name: String, itemId: UUID, entryId: UUID?) {
        guard let parentModel else { return }
        withAnimation {
            root.editControllable.addItem(itemId: itemId, parentId: parentModel.id)
            Task { await listController.performDetailSearch() }
            root.folderListControllable.resetFilter()
        }
    }

    private func deleteItems(offsets: IndexSet) {
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

    private func moveItems(source: IndexSet, destination: Int) {
        guard let parentModel else { return }
        root.editControllable.moveItems(source: source, destination: destination, itemId: parentModel.id)
    }

    private var leadingPadding: CGFloat {
        let value = listController.listDisplayModel.isSelectionMode ? 12 : 8
        return CGFloat(valueFor(iOS: value, macOS: 4, tvOS: value, visionOS: value))
    }
}

// MARK: - ListRowItemView
// Each row is its own struct so SwiftUI can skip body evaluation for unchanged rows.
// No closure parameters — all inputs are value/reference types enabling fast memcmp diffing.

private struct ListRowItemView: View {
    let root: any ItemRootControllable
    let item: FolderListItemModel
    let listController: any FolderListControllable
    let parentModel: (any ItemDataAccessable)?
    let menuController: ContextMenuMultiController
    let leadingPadding: CGFloat

    var body: some View {
        // Resolve the model once — avoids three separate dictionary lookups per render.
        let model = root.itemControllable.itemOrEmpty(for: item.source.itemId)
        HStack {
            ItemRowView(
                root: root,
                model: model,
                cacheItemListModel: listController.cacheListItemModel,
                listDisplayModel: listController.listDisplayModel,
                searchModel: listController.searchModel,
                isSelected: false
            ) {
                if root.viewControllable.thumbnailRowViewType == .custom {
                    root.viewControllable.thumbnailRowView(for: item.source.itemId)
                } else if root.viewControllable.thumbnailRowViewType == .photo,
                          let cacheController = root.cacheControllable {
                    ThumbnailRowPhotoView(
                        cacheController: cacheController,
                        model: model,
                        listDisplayModel: listController.listDisplayModel
                    )
                }
            }
            .draggable(for: root.configurable.module, itemId: item.source.itemId, entryId: nil, name: model.name)
            // Always-present contextMenu: empty closure = no menu when in selection mode
            .contextMenu {
                if !listController.listDisplayModel.isSelectionMode {
                    ListRootContextMenu(
                        root: root,
                        controller: menuController,
                        parentItem: parentModel,
                        currentSelected: item.source.itemId,
                        listController: listController
                    )
                }
            }

            SpecialCategoryFolderIndicator(
                item: item,
                isSpecialCategory: model.specialCategory,
                listController: listController
            )
        }
        .environment(listController.listDisplayModel)
        .padding(.leading, CGFloat(item.level * 16))
        .dropDestination(for: root.configurable.module, isEnabled: parentModel != nil, handler: addLink)
        .listRowInsets(EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0))
        .listRowSeparatorAll(item.isOpen ? .visible : .hidden, edges: .bottom)
    }

    private func addLink(name: String, itemId: UUID, entryId: UUID?) {
        guard let parentModel else { return }
        withAnimation {
            root.editControllable.addItem(itemId: itemId, parentId: parentModel.id)
            Task { await listController.performDetailSearch() }
            root.folderListControllable.resetFilter()
        }
    }
}

// MARK: - SpecialCategoryFolderIndicator
// Extracted so SwiftUI can skip the itemSync lookup and button rendering
// for rows whose folder-open state has not changed.

private struct SpecialCategoryFolderIndicator: View {
    let item: FolderListItemModel
    let isSpecialCategory: Bool
    let listController: any FolderListControllable

    var body: some View {
        if isSpecialCategory {
            Button {
                Task { await listController.toggleFolder(item: item) }
            } label: {
                Image(systemName: item.isOpen ? "chevron.down" : "chevron.right")
                    .imageScale(.small)
                    .padding(.trailing)
                    .foregroundStyle(item.isOpen ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .contentShape(.rect)
        }
    }
}

//#Preview("Split", traits: .mockData) {
//    @Previewable @Environment(FakeItemRootController.self) var root
//
//    ListRootView(root: root, parentModel: nil)
//}
