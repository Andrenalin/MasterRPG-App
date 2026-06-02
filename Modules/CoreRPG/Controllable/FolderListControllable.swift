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
    
    /// Runs a search, updates `searchModel.results`, and rebuilds `listModel.list`.
    /// Structured: if the enclosing `Task` is cancelled (e.g. view disappears or a
    /// newer search fires), this function exits at the next cancellation check and
    /// leaves the current list unchanged.
    @MainActor public func performSearch() async {
        searchModel.isSearching = true
        defer { searchModel.isSearching = false }

        let newResults = await searchRootControllable.results(text: searchModel.searchText)
        guard !Task.isCancelled else { return }
        searchModel.results = newResults
        withAnimation { resetFilter() }
    }

    /// Fire-and-forget variant for call sites that cannot `await` (e.g. synchronous
    /// protocol-extension callbacks like `resetParent`, `toggleFolder`).
    /// Assigning to `currentTask` auto-cancels the previous search via `didSet`.
    @MainActor func scheduleSearch() {
        searchModel.currentTask = Task { await performSearch() }
    }

    /// Runs a folder-scoped search for the detail list's parent and populates
    /// `listModel.detailListModel.list` with the matching children.
    @MainActor public func performDetailSearch() async {
        guard let detailListModel = listModel.detailListModel,
              let parentModel = detailListModel.parentModel else { return }
        let newResults = await searchRootControllable.results(
            text: searchModel.searchText,
            focusId: parentModel.id
        )
        guard !Task.isCancelled else { return }
        searchModel.detailResults = newResults
        detailListModel.list = buildDetailListItems()
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
    }

    func resetParent(model: (any ItemDataAccessable)?) {
        listModel.resetParent(model: model)
        listModel.updatedOnce = true
        // Scope the next search to this folder/collection's direct children
        searchRootControllable.searchModel.filterId = model?.id
        
        if let model {
            listDisplayModel.listMode <=> model.category == .folder ? .folder : .list
        }
        scheduleSearch()
    }
    
    /// Called when a folder/collection is selected as the detail page's parent.
    /// Creates (or resets) `listModel.detailListModel` scoped to `model`, then
    /// fires a background search to populate it.
    func resetDetail(model: (any ItemDataAccessable)) {
        listModel.resetDetailList(parentModel: model)
        listModel.detailListModel?.updatedOnce = true
        Task { await performDetailSearch() }
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
    /// Maps search results into `listModel.list`.
    /// The search owns the structure (`SearchResult.children`);
    /// this function only caches model identity and restores open state.
    func resetFilter() {
        listModel.list = buildList()
    }

    private func buildList() -> [FolderListItemModel] {
        let results = searchModel.results
        guard !results.isEmpty else { return listModel.list }
        let isSearching = !searchModel.searchText.isEmpty
        var flat: [FolderListItemModel] = []
        for result in results {
            appendToFlat(result: result, level: 0, isSearching: isSearching, flat: &flat)
        }
        return flat
    }

    /// Builds the detail list from `searchModel.detailResults`.
    private func buildDetailListItems() -> [FolderListItemModel] {
        let results = searchModel.detailResults
        guard !results.isEmpty else { return listModel.detailListModel?.list ?? [] }
        return results.map { mapResult($0, level: 0) }
    }

    /// Appends one search-result node (and, when open, its children) to the flat list.
    ///
    /// - When searching: auto-opens any item that has matched children.
    /// - When search is cleared: restores `lastIsOpen` so the user's explicit
    ///   open/close choices survive the round-trip through the search.
    private func appendToFlat(result: SearchResult, level: Int, isSearching: Bool, flat: inout [FolderListItemModel]) {
        let item = mapResult(result, level: level)

        // Sync children from what the search returned (search owns the structure)
        if !result.children.isEmpty {
            item.children = result.children.map { mapResult($0, level: level + 1) }
        }

        // Open state: search auto-opens matched folders; clears → restore user state.
        // shouldOpen overrides both (e.g. focused character inspector: always start expanded).
        if result.shouldOpen && !result.children.isEmpty {
            item.isOpen = true
            item.lastIsOpen = true   // persist so the state survives a search round-trip
        } else {
            item.isOpen = isSearching ? !result.children.isEmpty : item.lastIsOpen
        }

        flat.append(item)

        if item.isOpen {
            if !result.children.isEmpty {
                // Search returned children — recurse
                for childResult in result.children {
                    appendToFlat(result: childResult, level: level + 1, isSearching: isSearching, flat: &flat)
                }
            } else if !item.children.isEmpty {
                // Lazily-loaded children (from loadChildrenViaSearch) — include them
                flattenCachedChildren(item.children, into: &flat)
            }
        }
    }

    /// Returns the cached `FolderListItemModel` for `result`, or creates and caches a new one.
    /// Always syncs `canOpen` from the latest search result so the chevron reflects current state.
    private func mapResult(_ result: SearchResult, level: Int) -> FolderListItemModel {
        let id = result.entryId ?? result.itemId
        if let cached = listModel.cacheListModels[id] {
            cached.level = level
            cached.canOpen = result.canOpen
            return cached
        }
        let item = FolderListItemModel(
            id: id,
            source: ItemRowModel(itemId: result.itemId, entryId: result.entryId, typeId: result.module),
            destination: nil,
            level: level,
            isShown: false
        )
        item.canOpen = result.canOpen
        listModel.cacheListModels[id] = item
        return item
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

    /// Loads children via a scoped search — used when toggling a folder open during empty search
    /// and when a folder with `canOpen = true` is first expanded.
    ///
    /// Unlike the old synchronous `loadFolderChildren`, this uses the search pipeline so that:
    /// - Sub-folders are included with `canOpen = true` (no deeper pre-loading)
    /// - Sorting and filtering rules are applied consistently with the rest of the search
    /// - The code path is identical to `performDetailSearch` (reusable, testable)
    private func loadChildrenViaSearch(for item: FolderListItemModel) async {
        let results = await searchRootControllable.results(
            text: searchModel.searchText,
            focusId: item.source.itemId
        )
        guard !Task.isCancelled else { return }
        item.children = results.map { result in
            let child = mapResult(result, level: item.level + 1)
            child.parentId = item.id
            return child
        }
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
                if item.canOpen {
                    // Load children via scoped search (works for both empty and non-empty search).
                    // This is the same pipeline as performDetailSearch — folder items are
                    // returned with canOpen=true so they can be further expanded on demand.
                    await loadChildrenViaSearch(for: item)
                    resetFilter()
                } else {
                    // No pre-loaded children and canOpen=false: trigger a full re-search
                    // (e.g. search text changed and the item needs to re-evaluate matches).
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
              item.canOpen && !item.isOpen else { return }
        Task { await toggleFolder(item: item) }
    }

    /// Returns true if `itemId` is a closed item that can be expanded.
    /// Uses `FolderListItemModel.canOpen` — no extra `itemSync` call needed.
    func canOpenFolder(itemId: UUID?) -> Bool {
        guard let itemId,
              let item = listModel.list.first(where: { $0.source.itemId == itemId }) else { return false }
        return item.canOpen && !item.isOpen
    }

    /// Returns true if `itemId` has an open parent folder in the visible tree.
    func hasParentFolder(itemId: UUID?) -> Bool {
        guard let itemId,
              let item = listModel.list.first(where: { $0.source.itemId == itemId }),
              let parentId = item.parentId, let parentItem = listModel.cacheListModels[parentId] else { return false }
        return parentItem.isOpen
    }
}
