// @copyright André Trettin

import Foundation
import SwiftUI

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
    /// - Not `private`: also called from `FolderListControllable.swift`'s `performDetailSearch`.
    func buildDetailListItems() -> [FolderListItemModel] {
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
    /// - When searching: auto-opens matched children except lazy entry groups, which wait for
    ///   an explicit toggle so a parent-name match does not flood the visible list.
    /// - When search is cleared: restores `lastIsOpen` so the user's explicit
    ///   open/close choices survive the round-trip through the search.
    /// - `cache`: when non-nil, all items are read/written to this model's cache instead of
    ///   `listModel.cacheListModels`. Used by `buildDetailListItems` for isolation.
    /// - `level` doubles as a recursion-depth guard (see `FolderTreeDepthLimit`) — defense-in-depth
    ///   against a folder/collection cycle, which `EditControllable.addItem` already refuses to create.
    private func appendToFlat(result: SearchResult, level: Int, isSearching: Bool, flat: inout [FolderListItemModel], cache: FolderListModel? = nil) {
        guard level < FolderTreeDepthLimit.max else { return }
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
            let autoOpen = !isLazyExpandableEntryGroup(result) && !result.children.isEmpty && !item.wasExplicitlyClosed
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
        // Regular Characters are expandable in the link inspector, where the
        // disclosure reveals their value entries. The normal ListRootView uses
        // SearchListController and must reserve its disclosure for folders and
        // collections only.
        let canOpen = result.canOpen
            || (cache == nil
                && searchRootControllable is SearchLinkController
                && canExpandValueResult(result))
        if let cached = target.cacheListModels[id] {
            cached.level = level
            cached.canOpen = canOpen
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
        item.canOpen = canOpen
        item.childFocusId = result.childFocusId
        item.model = itemControllable.itemSync(for: result.itemId)
        target.cacheListModels[id] = item
        return item
    }

    private func isLazyExpandableEntryGroup(_ result: SearchResult) -> Bool {
        result.entryId != nil && result.canOpen && result.childFocusId != nil
    }

    private func canExpandValueResult(_ result: SearchResult) -> Bool {
        guard result.module == .value,
              result.entryId == nil,
              result.children.isEmpty,
              let model = itemControllable.itemSync(for: result.itemId) else { return false }
        return !model.entries.isEmpty
    }

    /// Expands open nodes in the cached children tree (lazy-loaded folder content).
    /// When `reload` is true (empty search), each open folder's children are refreshed from the
    /// live item model first, so membership changes propagate through the whole open subtree.
    /// `item.level` doubles as a recursion-depth guard (see `FolderTreeDepthLimit`).
    private func flattenCachedChildren(_ items: [FolderListItemModel], into flat: inout [FolderListItemModel], reload: Bool, cache: FolderListModel?) {
        for item in items {
            guard item.level < FolderTreeDepthLimit.max else { continue }
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
    /// - Not `private`: also called from `FolderListControllable+FolderLogic.swift`'s `toggleFolder`.
    func loadChildrenViaSearch(for item: FolderListItemModel, cache: FolderListModel? = nil) {
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
