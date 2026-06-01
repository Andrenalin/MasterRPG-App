// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor
public protocol FolderListControllable: Sendable {
    var itemControllable: any ItemControllable { get }

    var listModel: FolderListModel { get }
    var listDisplayModel: ListDisplayModel { get }
    var searchModel: SearchModel { get }
    var cacheListItemModel: CacheItemListModel { get }
    var searchRootControllable: any SearchRootControllable { get }

    func copy(listModel: FolderListModel) -> Self
    
    func detailDestination(for itemId: UUID) -> any NavigationDestination
    func viewerDestination(for itemId: UUID) -> any NavigationDestination
}

extension FolderListControllable {
    public var searchModel: SearchModel { searchRootControllable.searchModel }

    @MainActor public func performSearch() async {
        searchRootControllable.searchModel.results = []
        //resetFilter()
        await searchRootControllable.performSearch()
        resetFilter()
    }

    public func copyModel(parentModel: (any ItemDataAccessable)?) -> FolderListModel {
        FolderListModel(parentModel: parentModel, navigationModel: listModel.navigationModel)
    }

    public func resetItemOnce() {
        guard listModel.updatedOnce == false else { return }
        listModel.updatedOnce = true
        resetFilter()
    }

    /// Resets the parent model and triggers filtering updates.
    /// When a parent model is set, the list mode is controlled by LinkItemListView.configureParentFiltering()
    /// based on the parent's category (folder → .folder mode, others → .list mode).
    /// UI controls for list mode should be disabled when parentModel is set.
    public func resetParentModel(model: (any ItemDataAccessable)) {
        if listModel.parentModel?.id != model.id {
            listModel.updatedOnce = true
            listModel.parentModel = model
            resetFilter()
        }
    }
    
    public func selectedModel(for selectedId: UUID?) -> (any ItemDataAccessable)? {
        itemControllable.itemSync(for: selectedId ?? listModel.selected ?? UUID())
    }
}

public extension FolderListControllable {
    func update() {
        let previousSelectedId = listModel.selectedItemId

        resetFilter()

        if let addedModelId = listModel.addedModelId,
           let addedItem = listModel.list.first(where: { $0.source.itemId == addedModelId }) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                listModel.listSelection = Set(arrayLiteral: addedItem.id)
            }
            listModel.addedModelId = nil
        } else if let itemId = previousSelectedId ?? listModel.navigationModel.selectedItemId,
                  let newSelected = listModel.list.first(where: { $0.source.itemId == itemId }) {
            listModel.listSelection = Set(arrayLiteral: newSelected.id)
            listModel.selected = newSelected.id
            listModel.scrollId = newSelected.id
        }
    }
}

extension FolderListControllable {
    func add(type: EditControllerAddType, url: URL?, root: any ItemRootControllable) {
        Task {
            guard let model = await root.editControllable.addNew(type: type) else { return }
            if let url {
                await root.editControllable.resetFile(url: url, itemId: model.id)
                let cc = ConvertController(itemController: root.itemControllable, editController: root.editControllable)
                await cc.moveAndCreateFolders(itemId: model.id)
            }
            try? await Task.sleep(for: .seconds(1.0))
            await root.itemControllable.save()
            if listModel.parentModel != nil {
                root.editControllable.addItem(itemId: model.id, parentId: listModel.selectedParentId)
                // Reset parent list filter when adding to folder/collection
                root.folderListControllable.resetFilter()
            }
            guard let updatedModel = root.itemControllable.itemSync(for: model.id) else { return }
            add(model: updatedModel)
            resetFilter()
            listModel.set(selectedItemId: updatedModel.id)
            listModel.scrollId = listModel.selected
            try? await Task.sleep(for: .seconds(0.25))
            root.navigationModel.openHeaderEditor = true
        }
    }
    
    private func add(model: any ItemDataAccessable) {
        listModel.addedModelId = model.id
    }
    
    @MainActor func delete(offsets: IndexSet) -> [ItemRowModel] {
        let removed = offsets.map {
            let source = listModel.list[$0].source
            return ItemRowModel(itemId: source.itemId, typeId: itemControllable.config.module)
        }
        listModel.deleteItems(offsets: offsets)
        return removed
    }
}

// MARK: Folder Logic

extension FolderListControllable {
    func toggleFolder(item: FolderListItemModel) async {
        if item.isOpen {
            item.isOpen = false
        } else {
            // might be reload data
            item.isOpen = true
            if item.children.isEmpty {
                await performSearch()
            }
        }
    }
}

// MARK: Search & Filter

extension FolderListControllable {
    func resetFilter() {
        listModel.list = buildListItems()
    }
    
    private func buildListItems() -> [FolderListItemModel] {
        if listDisplayModel.listMode == .list {
            return buildList()
        } else {
            return buildFolder()
        }
    }
    
    private func buildList() -> [FolderListItemModel] {
        let results = searchModel.results
        // Search results are populated asynchronously. While they are pending (empty),
        // preserve the current list so no flash-to-empty occurs mid-transition.
        guard !results.isEmpty else { return listModel.list }
        return results.map {
            if let cached = listModel.cacheListModels[$0.itemId] {
                return cached
            }
            let newModel = FolderListItemModel(id: $0.itemId, source: ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module), destination: nil, level: 0, isShown: true)
            listModel.cacheListModels[$0.itemId] = newModel
            return newModel
        }
    }

    private func buildFolder() -> [FolderListItemModel] {
        let results = searchModel.results
        guard !results.isEmpty else { return listModel.list }
        return results.map {
            if let cached = listModel.cacheListModels[$0.itemId] {
                return cached
            }
            let newModel = FolderListItemModel(id: $0.itemId, source: ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module), destination: nil, level: 0, isShown: true)
            listModel.cacheListModels[$0.itemId] = newModel
            return newModel
        }
    }
}

extension FolderListControllable {
    func toggleParentFolder(item: FolderListItemModel) {
        listModel.toggleFolder(itemId: item.source.itemId, entryId: nil)
        guard let parentItem = listModel.list.first(where: {
            $0.source.itemId == item.source.itemId && $0.source.entryId == nil && $0.level == item.level - 1
        }) else { return }
        parentItem.isOpen.toggle()
        resetFilter()
    }

    /// Closes the nearest open parent folder of the currently selected item
    /// and selects that parent folder afterwards.
    func closeParentFolder() {
        guard let itemId = listModel.selectedItemId else { return }
        closeParentFolder(of: itemId)
    }

    /// Opens the selected item if it is a closed folder.
    func openSelectedFolder() {
        guard let itemId = listModel.selectedItemId else { return }
        openFolder(itemId: itemId)
    }

    /// Closes the nearest open parent folder of `itemId` and selects that parent folder.
    func closeParentFolder(of itemId: UUID) {
        guard let index = listModel.list.firstIndex(where: { $0.source.itemId == itemId }) else { return }
        let selectedLevel = listModel.list[index].level
        for i in stride(from: index - 1, through: 0, by: -1) {
            let candidate = listModel.list[i]
            guard candidate.level < selectedLevel,
                  let model = itemControllable.itemSync(for: candidate.source.itemId),
                  model.specialCategory && candidate.isOpen else { continue }
            Task { await toggleFolder(item: candidate) }
            listModel.selected = candidate.source.itemId
            listModel.listSelection = Set(arrayLiteral: candidate.source.itemId)
            listModel.scrollId = candidate.source.itemId
            listModel.navigationModel.selectedItemId = candidate.source.itemId
            return
        }
    }

    /// Opens `itemId` if it is a closed folder.
    func openFolder(itemId: UUID) {
        guard let item = listModel.list.first(where: { $0.source.itemId == itemId }),
              let model = itemControllable.itemSync(for: item.source.itemId),
              model.specialCategory && !item.isOpen else { return }
        Task { await toggleFolder(item: item) }
    }

    /// Returns true if `itemId` is a closed folder that can be opened.
    func canOpenFolder(itemId: UUID?) -> Bool {
        guard let itemId,
              let item = listModel.list.first(where: { $0.source.itemId == itemId }),
              let model = itemControllable.itemSync(for: item.source.itemId) else { return false }
        return model.specialCategory && !item.isOpen
    }

    /// Returns true if `itemId` has an open parent folder in the visible tree.
    func hasParentFolder(itemId: UUID?) -> Bool {
        guard let itemId,
              let index = listModel.list.firstIndex(where: { $0.source.itemId == itemId }),
              index > 0 else { return false }
        let selectedLevel = listModel.list[index].level
        return listModel.list[0..<index].contains { item in
            guard let model = itemControllable.itemSync(for: item.source.itemId) else { return false }
            return item.level < selectedLevel && model.specialCategory && item.isOpen
        }
    }
}

