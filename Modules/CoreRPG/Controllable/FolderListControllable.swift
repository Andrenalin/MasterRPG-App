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
        await searchRootControllable.performSearch()
        resetFilter()
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
    
    func copyModel(parentModel: (any ItemDataAccessable)?) -> FolderListModel {
        let newModel = FolderListModel(parentModel: parentModel, navigationModel: listModel.navigationModel)
        // Pre-populate the cache with any already-loaded children of the parent folder/collection
        // so the detail list can render immediately while the background search runs.
        if let parentModel {
            for entry in parentModel.entries {
                // Children are keyed by entry.id (folder membership identity)
                if let cached = listModel.cacheListModels[entry.id] {
                    newModel.cacheListModels[entry.id] = cached
                }
                // Also try childId for items cached in list mode (id == itemId)
                let childId = entry.childId
                if childId != entry.id, let cached = listModel.cacheListModels[childId] {
                    newModel.cacheListModels[childId] = cached
                }
            }
        }
        return newModel
    }

    func resetItemOnce() async {
        guard listModel.updatedOnce == false else { return }
        listModel.updatedOnce = true
        await performSearch()
        resetFilter()
    }

    /// Called when a folder/collection is selected as the detail page's parent.
    /// Sets filterId so the search is scoped to this item's children, switches to
    /// folder mode (required for focusId to be forwarded to the search), and
    /// triggers the search so children appear immediately.
    func resetParentModel(model: (any ItemDataAccessable)) {
        if listModel.parentModel?.id != model.id {
            listModel.updatedOnce = true
            listModel.parentModel = model
            // Scope the next search to this folder/collection's direct children
            searchRootControllable.searchModel.filterId = model.id
            listDisplayModel.listMode = .folder
            Task { await performSearch() }
        }
    }
    
    func selectedModel(for selectedId: UUID?) -> (any ItemDataAccessable)? {
        itemControllable.itemSync(for: selectedId ?? listModel.selected ?? UUID())
    }
}

// MARK: List change

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
            listModel.addedModelId = model.id
            resetFilter()
            listModel.set(selectedItemId: updatedModel.id)
            listModel.scrollId = listModel.selected
            try? await Task.sleep(for: .seconds(0.25))
            root.navigationModel.openHeaderEditor = true
        }
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
        var flat: [FolderListItemModel] = []
        flattenResults(results, level: 0, parentId: nil, into: &flat)
        return flat
    }

    private func flattenResults(_ results: [SearchResult], level: Int, parentId: UUID?, into flat: inout [FolderListItemModel]) {
        let isSearching = !searchModel.searchText.isEmpty
        for result in results {
            let item = folderItem(from: result, level: level, parentId: parentId)
            if !result.children.isEmpty {
                // Active search: populate children from matching results and auto-open.
                item.children = result.children.map { folderItem(from: $0, level: level + 1, parentId: item.id) }
                item.isOpen = isSearching ? true : item.lastIsOpen
            } else if !isSearching {
                // Empty search (lazy mode): restore the user's open state and,
                // if the folder is open, refresh its direct children from the item model.
                item.isOpen = item.lastIsOpen
                if item.isOpen {
                    loadFolderChildren(for: item)
                }
            }
            flat.append(item)
            if item.isOpen {
                if !result.children.isEmpty {
                    flattenResults(result.children, level: level + 1, parentId: item.id, into: &flat)
                } else if !item.children.isEmpty {
                    flattenCachedChildren(item.children, into: &flat)
                }
            }
        }
    }

    // Expands open nodes in the cached children tree (used for lazy-loaded folder content).
    private func flattenCachedChildren(_ items: [FolderListItemModel], into flat: inout [FolderListItemModel]) {
        for item in items {
            flat.append(item)
            if item.isOpen && !item.children.isEmpty {
                flattenCachedChildren(item.children, into: &flat)
            }
        }
    }

    // Loads the direct children of a folder/collection from the item model into item.children.
    // Called for lazy expansion during empty search so no re-search is needed.
    private func loadFolderChildren(for item: FolderListItemModel) {
        guard let folder = itemControllable.itemSync(for: item.source.itemId) else { return }
        var children: [FolderListItemModel] = []
        for entry in folder.entries {
            guard let childModel = itemControllable.itemSync(for: entry.childId),
                  childModel.displayState == 0 else { continue }
            let id = entry.id
            if let cached = listModel.cacheListModels[id] {
                cached.level = item.level + 1
                cached.parentId = item.id
                children.append(cached)
            } else {
                let child = FolderListItemModel(
                    id: id,
                    source: ItemRowModel(itemId: childModel.id, entryId: entry.id, typeId: itemControllable.config.module),
                    destination: nil,
                    level: item.level + 1,
                    isShown: !childModel.specialCategory
                )
                child.parentId = item.id
                listModel.cacheListModels[id] = child
                children.append(child)
            }
        }
        if folder.category == .folder {
            children.sort {
                let a = itemControllable.itemSync(for: $0.source.itemId)?.name ?? ""
                let b = itemControllable.itemSync(for: $1.source.itemId)?.name ?? ""
                return a.localizedCompare(b) == .orderedAscending
            }
        }
        item.children = children
    }

    // id: entry.id when the item is a child inside a folder/collection (so the same item
    // appearing in multiple collections gets independent SwiftUI identity and cache slots).
    // For root-level items entryId is nil, so itemId is used.
    private func folderItem(from result: SearchResult, level: Int, parentId: UUID?) -> FolderListItemModel {
        let id = result.entryId ?? result.itemId
        if let cached = listModel.cacheListModels[id] {
            cached.level = level
            cached.parentId = parentId
            return cached
        }
        let isSpecial = itemControllable.itemSync(for: result.itemId)?.specialCategory ?? false
        let item = FolderListItemModel(
            id: id,
            source: ItemRowModel(itemId: result.itemId, entryId: result.entryId, typeId: result.module),
            destination: nil,
            level: level,
            isShown: !isSpecial
        )
        item.parentId = parentId
        listModel.cacheListModels[id] = item
        return item
    }
}

// MARK: Folder Logic

extension FolderListControllable {
    func toggleFolder(item: FolderListItemModel) async {
        if item.isOpen {
            item.isOpen = false
            item.lastIsOpen = false
            resetFilter()
        } else {
            item.isOpen = true
            item.lastIsOpen = true
            if item.children.isEmpty {
                if searchModel.searchText.isEmpty {
                    // Empty search: load children directly from the item model — no re-search needed.
                    loadFolderChildren(for: item)
                    resetFilter()
                } else {
                    await performSearch()
                }
            } else {
                resetFilter()
            }
        }
    }

    func toggleParentFolder(item: FolderListItemModel) {
        guard let parentId = item.parentId, let parentItem = listModel.cacheListModels[parentId] else { return }
        parentItem.isOpen.toggle()
        parentItem.lastIsOpen = parentItem.isOpen  // Mirror user's explicit choice
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
        guard let item = listModel.list.first(where: { $0.source.itemId == itemId }) else { return }
        guard let parentId = item.parentId, let parentItem = listModel.cacheListModels[parentId] else { return }
        parentItem.isOpen = false
        listModel.selected = parentId
        listModel.listSelection = Set(arrayLiteral: parentId)
        listModel.scrollId = parentId
        listModel.navigationModel.selectedItemId = parentItem.source.itemId
    }

    /// Opens `itemId` if it is a closed folder.
    func openFolder(itemId: UUID) {
        guard let item = listModel.list.first(where: { $0.source.itemId == itemId }),
              let model = itemControllable.itemSync(for: item.source.itemId), // replace this item.mode(root: RootManager) call
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
              let item = listModel.list.first(where: { $0.source.itemId == itemId }),
              let parentId = item.parentId, let parentItem = listModel.cacheListModels[parentId] else { return false }
        return parentItem.isOpen
    }
}
