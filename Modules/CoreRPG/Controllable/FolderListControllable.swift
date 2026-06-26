// @copyright André Trettin

import Foundation
import SwiftUI
import os

/// Distinguishes the two search targets the single search pipeline can run.
enum FolderSearchKind: Sendable { case root, detail }

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
    func folderDestination(for itemId: UUID) -> any NavigationDestination
    func viewerDestination(for itemId: UUID) -> any NavigationDestination
}

extension FolderListControllable {
    public var searchModel: SearchModel { searchRootControllable.searchModel }
    
    /// Runs a search, updates `searchModel.results`, and rebuilds `listModel.list`.
    /// Structured: if the enclosing `Task` is cancelled (e.g. view disappears or a
    /// newer search fires), this function exits at the next cancellation check and
    /// leaves the current list unchanged.
    @MainActor public func performSearch(source: String) async {
        let startTime = ContinuousClock.now
        let searchText = searchModel.searchText
        let displayMode = listDisplayModel.displayMode
        
        Logger.folderListControllable.info("🔍 [Search] Starting ASYNC search - source: '\(source)', text: '\(searchText)', displayMode: \(displayMode.rawValue)")
        
        searchModel.isSearching = true
        defer { searchModel.isSearching = false }

        let newResults = await searchRootControllable.results(text: searchModel.searchText)
        guard !Task.isCancelled else {
            Logger.folderListControllable.info("⚠️ [Search] Cancelled - source: '\(source)', text: '\(searchText)'")
            return
        }
        searchModel.results = newResults
        searchModel.searchReturnedNoResults = !searchModel.searchText.isEmpty && newResults.isEmpty
        withAnimation { resetFilter() }
        
        let duration = ContinuousClock.now - startTime
        Logger.folderListControllable.info("✅ [Search] Completed ASYNC - source: '\(source)', text: '\(searchText)', displayMode: \(displayMode.rawValue), duration: \(duration), results: \(newResults.count)")
    }

    /// Single coalescing entry point for every search trigger. Assigning `searchModel.currentTask`
    /// cancels any in-flight search (its `didSet`), so rapid triggers — keystrokes, mode toggles,
    /// and the observation stream — collapse into one search instead of one-per-event. The 300ms
    /// debounce applies only while typing a non-empty query; every other trigger uses a short
    /// coalescing window so bursts still settle into a single call.
    @MainActor func runSearch(source: String, kind: FolderSearchKind, debounceText: Bool) {
        searchModel.currentTask = Task {
            let delay: Duration = debounceText && !searchModel.searchText.isEmpty ? .milliseconds(300) : .milliseconds(50)
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            switch kind {
            case .root: await performSearch(source: source)
            case .detail: await performDetailSearch()
            }
        }
    }

    /// Fire-and-forget root search for call sites that cannot `await` (e.g. synchronous
    /// protocol-extension callbacks like `resetParent`, `toggleFolder`, and the search field).
    @MainActor func scheduleSearch() {
        runSearch(source: "scheduleSearch", kind: .root, debounceText: true)
    }

    /// Runs a scoped search for the detail list's parent and populates
    /// `listModel.detailListModel.list` with the results.
    ///
    /// Uses `results(text:)` with `filterId = parentModel.id` — the same pipeline as
    /// `performSearch` / `scheduleSearch`. This routes through `inspectorSearchResults`
    /// which correctly handles per-module overrides (e.g. CharacterRPG `focusedCharacterInspector`
    /// returns the character as a root item with entries as children).
    ///
    /// `results(text:, focusId:)` is NOT used here because that path is reserved for
    /// `loadChildrenViaSearch` where the expected return is flat entry/child results —
    /// not an item-as-root structure.
    @MainActor public func performDetailSearch() async {
        guard let detailListModel = listModel.detailListModel,
              let parentModel = detailListModel.parentModel else { return }
        // scopedResults — semantically "show this item as the root of the detail view":
        //   SearchListController: folder-mode listSearchResults(focusId:) → parent's children.
        //   SearchLinkController: list-mode inspectorSearchResults(focusId:) → character-as-root
        //     (via focusedCharacterInspector) or collection children (via inspectorScopedListResults).
        // Does NOT use results(text:, focusId:) which is exclusively for loadChildrenViaSearch.
        let newResults = await searchRootControllable.scopedResults(
            text: searchModel.searchText,
            focusId: parentModel.id
        )
        guard !Task.isCancelled else { return }
        searchModel.detailResults = newResults
        detailListModel.list = buildDetailListItems()
    }
}

public extension FolderListControllable {
    /// Data-change refresh (observation stream, context-menu moves). Routes the search through the
    /// single `currentTask` so it coalesces with — and never clobbers — an in-flight user search,
    /// then applies selection/scroll fix-up only after the (coalesced) search has rebuilt the list.
    /// - `debounce`: the observation stream passes `true` to coalesce bursts; explicit user actions
    ///   (context-menu move/add/remove) pass `false` so the list rebuilds immediately and reliably.
    func update(debounce: Bool = true) {
        let previousSelectedId = listModel.selectedItemId
        if let addedModelId = listModel.addedModelId,
           let addedItem = listModel.list.first(where: { $0.source.itemId == addedModelId }) {
            listModel.selected = addedItem.id
        }

        searchModel.currentTask = Task {
            if debounce {
                // Coalesce a burst of data changes into one search.
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            // Always refresh the root results: resetFilter rebuilds listModel.list from
            // searchModel.results, so a move/add/remove must re-run performSearch to drop the item
            // from the root level. (Routing only to performDetailSearch left listModel.list rebuilt
            // from stale results — the moved item stayed at its old root position.)
            await performSearch(source: "update")
            // Additionally refresh an active scoped detail list (e.g. the focused character
            // inspector), whose rows come from detailResults rather than the root results.
            if listModel.detailListModel != nil {
                guard !Task.isCancelled else { return }
                await performDetailSearch()
            }
            guard !Task.isCancelled else { return }
            applyPostUpdateSelection(previousSelectedId: previousSelectedId)
        }
    }

    /// Restores selection/scroll after `update()`'s search has rebuilt the list.
    private func applyPostUpdateSelection(previousSelectedId: UUID?) {
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
        await performSearch(source: "resetItemOnce")
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
    /// Creates (or resets) `listModel.detailListModel` scoped to `model`, then populates it.
    ///
    /// The initial populate runs in its own task rather than the shared search token: the sibling
    /// initial triggers (`listMode`/`displayMode` `onChange(initial:)` and the observation stream)
    /// assign `currentTask` around the same time and would otherwise cancel this first populate
    /// before the detail list is ever built — the cause of the focused inspector being blank on
    /// first launch. Subsequent filter-field searches still go through the coalescing pipeline.
    /// The detail cache is warm-started in `copyModel`, so revisited parents redisplay instantly.
    func resetDetail(model: (any ItemDataAccessable)) {
        listModel.resetDetailList(parentModel: model)
        listModel.detailListModel?.updatedOnce = true
        Task { await performDetailSearch() }
    }

    /// Fire-and-forget scoped detail search — used by `LinkItemListView` / `resetDetail` when
    /// `parentModel != nil`. Routes through the single coalescing pipeline (`runSearch`).
    @MainActor func scheduleDetailSearch() {
        runSearch(source: "scheduleDetailSearch", kind: .detail, debounceText: true)
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
        // When a detail model is active (scoped inspector / focused character inspector),
        // also rebuild it so toggle actions are immediately reflected in the detail view.
        // Without this, resetFilter only updates listModel.list (the main list) while the
        // view reads detailListModel.list — causing toggle to appear as a no-op.
        if let detail = listModel.detailListModel {
            detail.list = buildDetailListItems()
        }
    }

    private func buildList() -> [FolderListItemModel] {
        let results = searchModel.results
        guard !results.isEmpty else { return listModel.list }
        let isSearching = !searchModel.searchText.isEmpty
        var flat: [FolderListItemModel] = []
        for result in results {
            appendToFlat(result: result, level: 0, isSearching: isSearching, flat: &flat)
        }
        // Requirement: the currently selected item is always included in non-empty search results,
        // even when it doesn't match the filter. This keeps the selection visible so the user
        // doesn't lose context while searching.
        // `listModel.selected` holds the FolderListItemModel.id of the selected row; the cache is
        // keyed by that same id, so the lookup is O(1).
        if isSearching,
           let selected = listModel.selected,
           !flat.contains(where: { $0.id == selected }),
           let cached = listModel.cacheListModels[selected] {
            cached.level = 0   // force root level — selected item appears as a standalone result
            flat.append(cached)
        }
        return flat
    }

    /// Builds the detail list from `searchModel.detailResults` using `appendToFlat`.
    ///
    /// Passes `targetModel = detailListModel` so ALL items (character, entries, sub-entries)
    /// are cached in `detailListModel.cacheListModels` — completely isolated from
    /// `listModel.cacheListModels` (the common inspector cache). This prevents detail state
    /// (open/close of character entries) from leaking back into the common inspector when the
    /// user switches modules.
    private func buildDetailListItems() -> [FolderListItemModel] {
        let detailModel = listModel.detailListModel
        let results = searchModel.detailResults
        guard !results.isEmpty else { return detailModel?.list ?? [] }
        let isSearching = !searchModel.searchText.isEmpty
        var flat: [FolderListItemModel] = []
        for result in results {
            appendToFlat(result: result, level: 0, isSearching: isSearching, flat: &flat, cache: detailModel)
        }
        return flat
    }

    /// Appends one search-result node (and, when open, its children) to the flat list.
    ///
    /// - When searching: auto-opens any item that has matched children.
    /// - When search is cleared: restores `lastIsOpen` so the user's explicit
    ///   open/close choices survive the round-trip through the search.
    /// - `cache`: when non-nil, all items are read/written to this model's cache instead of
    ///   `listModel.cacheListModels`. Used by `buildDetailListItems` for isolation.
    private func appendToFlat(result: SearchResult, level: Int, isSearching: Bool, flat: inout [FolderListItemModel], cache: FolderListModel? = nil) {
        let item = mapResult(result, level: level, cache: cache)

        // Sync children from what the search returned (search owns the structure)
        if !result.children.isEmpty {
            item.children = result.children.map { mapResult($0, level: level + 1, cache: cache) }
        }

        // Open state: search auto-opens matched folders; clears → restore user state.
        // shouldOpen overrides both (e.g. focused character inspector: always start expanded).
        if result.shouldOpen && !result.children.isEmpty {
            item.isOpen = true
            item.lastIsOpen = true   // persist so the state survives a search round-trip
        } else if isSearching {
            // Search found children + user never explicitly closed → auto-open.
            let autoOpen = !result.children.isEmpty && !item.wasExplicitlyClosed
            // User manually opened during search (item.children loaded, lastIsOpen=true) → stay open.
            let userOpenedDuringSearch = !item.children.isEmpty && item.lastIsOpen
            item.isOpen = autoOpen || userOpenedDuringSearch
        } else {
            // Not searching: restore lastIsOpen (user's last explicit choice).
            item.isOpen = item.lastIsOpen
        }

        flat.append(item)

        if item.isOpen {
            if !result.children.isEmpty {
                // Search returned children — recurse, keeping the same cache
                for childResult in result.children {
                    appendToFlat(result: childResult, level: level + 1, isSearching: isSearching, flat: &flat, cache: cache)
                }
            } else if !isSearching {
                // Empty search returns folders without children, so reload this open folder's
                // children from the live item model. Keeps the tree in sync after a move/add/remove
                // of folder membership without a re-toggle; mapResult reuses cached rows, so nested
                // open/close state is preserved.
                if item.canOpen { loadChildrenViaSearch(for: item, cache: cache) }
                flattenCachedChildren(item.children, into: &flat, reload: true, cache: cache)
            } else if !item.children.isEmpty {
                // Active search: folder matched by name but no child matched — keep loaded children.
                flattenCachedChildren(item.children, into: &flat, reload: false, cache: cache)
            }
        }
    }

    /// Returns the cached `FolderListItemModel` for `result`, or creates and caches a new one.
    /// Always syncs `canOpen` from the latest search result so the chevron reflects current state.
    ///
    /// - `cache`: when non-nil, reads/writes from this model's `cacheListModels` instead of
    ///   `listModel.cacheListModels`. This keeps detail items isolated from the common inspector.
    private func mapResult(_ result: SearchResult, level: Int, cache: FolderListModel? = nil) -> FolderListItemModel {
        let target = cache ?? listModel
        let id = result.entryId ?? result.itemId
        if let cached = target.cacheListModels[id] {
            cached.level = level
            cached.canOpen = result.canOpen
            cached.childFocusId = result.childFocusId
            if cached.model == nil {
                cached.model = itemControllable.itemSync(for: result.itemId)
            }
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
        item.childFocusId = result.childFocusId
        item.model = itemControllable.itemSync(for: result.itemId)
        target.cacheListModels[id] = item
        return item
    }

    /// Expands open nodes in the cached children tree (lazy-loaded folder content).
    /// When `reload` is true (empty search), each open folder's children are refreshed from the
    /// live item model first, so membership changes propagate through the whole open subtree.
    private func flattenCachedChildren(_ items: [FolderListItemModel], into flat: inout [FolderListItemModel], reload: Bool, cache: FolderListModel?) {
        for item in items {
            flat.append(item)
            guard item.isOpen else { continue }
            if reload, item.canOpen {
                loadChildrenViaSearch(for: item, cache: cache)
            }
            if !item.children.isEmpty {
                flattenCachedChildren(item.children, into: &flat, reload: reload, cache: cache)
            }
        }
    }

    /// Loads children synchronously via `syncExpandResults` — no async needed because the data
    /// is already in memory (`itemSync` dictionary lookup). Called when the user taps a chevron and
    /// when rebuilding an open folder in empty-search mode.
    /// - `cache`: when non-nil, children are written to this model's cache (detail isolation);
    ///   when nil, falls back to detecting the detail cache from the item's presence in it.
    private func loadChildrenViaSearch(for item: FolderListItemModel, cache: FolderListModel? = nil) {
        let focusId = item.childFocusId ?? item.source.itemId
        let results = searchRootControllable.syncExpandResults(focusId: focusId)
        // Route children to the same cache as their parent for detail/common isolation.
        let detail = listModel.detailListModel
        let resolvedCache: FolderListModel? = cache ?? (detail?.cacheListModels[item.id] != nil ? detail : nil)
        item.children = results.map { result in
            let child = mapResult(result, level: item.level + 1, cache: resolvedCache)
            child.parentId = item.id
            return child
        }
    }
}

// MARK: Folder Logic

extension FolderListControllable {
    /// Fully synchronous — `loadChildrenViaSearch` uses `syncExpandResults` (pure `itemSync` map).
    /// The old `async` + `await performSearch()` else-branch was dead code: reaching
    /// `canOpen=false && children=[]` requires `wasExplicitlyClosed=true`, which in turn
    /// requires a prior open that already populated `children`. See sync-concurrency analysis.
    func toggleFolder(item: FolderListItemModel) {
        if item.isOpen {
            item.isOpen = false
            item.lastIsOpen = false
            item.wasExplicitlyClosed = true
            resetFilter()
        } else {
            item.isOpen = true
            item.lastIsOpen = true
            item.wasExplicitlyClosed = false
            if item.children.isEmpty && item.canOpen {
                loadChildrenViaSearch(for: item)
            }
            resetFilter()
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

    /// Opens `itemId` if it is a closed folder that can be expanded or was explicitly closed.
    func openFolder(itemId: UUID) {
        guard let item = listModel.list.first(where: { $0.source.itemId == itemId }),
              (item.canOpen || item.wasExplicitlyClosed) && !item.isOpen else { return }
        toggleFolder(item: item)
    }

    /// Returns true if `itemId` is a closed item that can be expanded or was explicitly closed.
    func canOpenFolder(itemId: UUID?) -> Bool {
        guard let itemId,
              let item = listModel.list.first(where: { $0.source.itemId == itemId }) else { return false }
        return (item.canOpen || item.wasExplicitlyClosed) && !item.isOpen
    }

    /// Returns true if `itemId` has an open parent folder in the visible tree.
    func hasParentFolder(itemId: UUID?) -> Bool {
        guard let itemId,
              let item = listModel.list.first(where: { $0.source.itemId == itemId }),
              let parentId = item.parentId, let parentItem = listModel.cacheListModels[parentId] else { return false }
        return parentItem.isOpen
    }
}
