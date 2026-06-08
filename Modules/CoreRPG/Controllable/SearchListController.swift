// @copyright André Trettin

import Foundation

@MainActor
public struct SearchListController {
    public init(searchController: any SearchControllable, searchModel: SearchModel, listDisplayModel: ListDisplayModel) {
        self.searchController = searchController
        self.searchModel = searchModel
        self.listDisplayModel = listDisplayModel
    }

    let searchController: any SearchControllable
    public let searchModel: SearchModel
    public let listDisplayModel: ListDisplayModel
}

extension SearchListController: SearchRootControllable {
    public func results(text: String) async -> [SearchResult] {
        await searchController.listSearchResults(
            searchText: text,
            listMode: listDisplayModel.listMode,
            displayMode: listDisplayModel.displayMode,
            focusId: listDisplayModel.listMode == .folder ? searchModel.filterId : nil
        )
    }

    /// Synchronous in-memory search using itemSync.
    /// Mirrors the async `results` logic but uses only synchronous item access.
    public func syncResults(text: String) -> [SearchResult] {
        searchController.syncListSearchResults(
            searchText: text,
            listMode: listDisplayModel.listMode,
            displayMode: listDisplayModel.displayMode,
            focusId: listDisplayModel.listMode == .folder ? searchModel.filterId : nil
        )
    }

    /// Child/entry expansion: always uses folder mode so folder children are returned.
    public func results(text: String, focusId: UUID) async -> [SearchResult] {
        await searchController.listSearchResults(
            searchText: text,
            listMode: .folder,
            displayMode: listDisplayModel.displayMode,
            focusId: focusId
        )
    }

    /// Scoped view for `performDetailSearch`: folder mode to return the parent's children.
    public func scopedResults(text: String, focusId: UUID) async -> [SearchResult] {
        await searchController.listSearchResults(
            searchText: text,
            listMode: .folder,
            displayMode: listDisplayModel.displayMode,
            focusId: focusId
        )
    }

    /// Sync expansion: folder/collection children only (list search never expands item entries).
    @MainActor public func syncExpandResults(focusId: UUID) -> [SearchResult] {
        guard let item = searchController.itemControllable.itemSync(for: focusId),
              item.specialCategory else { return [] }
        let results = item.entries.compactMap { entry -> SearchResult? in
            guard let child = searchController.itemControllable.itemSync(for: entry.childId),
                  child.displayState == 0 else { return nil }
            let entryId = entry.id == entry.childId ? entry.id.childPath(of: item.id) : entry.id
            var result = SearchResult(
                itemId: child.id, itemName: child.name,
                module: searchController.itemControllable.config.module,
                category: child.category,
                entryId: entryId, entryName: nil, matchedContent: nil, relevanceScore: 0
            )
            result.canOpen = child.specialCategory  // nested folders can themselves be expanded
            return result
        }
        // Folders: alphabetical order. Collections: preserve entry order.
        if item.category == .folder {
            return results.sorted { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
        }
        return results
    }

    public func copy(listDisplayModel: ListDisplayModel) -> any SearchRootControllable {
        SearchListController(
            searchController: searchController,
            searchModel: searchModel.newSearchModel,
            listDisplayModel: listDisplayModel
        )
    }
}


@MainActor
public struct SearchLinkController {
    public init(searchController: any SearchControllable, searchModel: SearchModel, listDisplayModel: ListDisplayModel) {
        self.searchController = searchController
        self.searchModel = searchModel
        self.listDisplayModel = listDisplayModel
    }

    let searchController: any SearchControllable
    public let searchModel: SearchModel
    public let listDisplayModel: ListDisplayModel
}

extension SearchLinkController: SearchRootControllable {
    public func results(text: String) async -> [SearchResult] {
        await searchController.inspectorSearchResults(
            searchText: text,
            listMode: listDisplayModel.listMode,
            displayMode: listDisplayModel.displayMode,
            focusId: searchModel.filterId
        )
    }

    /// Synchronous in-memory search using itemSync.
    /// Mirrors the async `results` logic but uses only synchronous item access.
    public func syncResults(text: String) -> [SearchResult] {
        searchController.syncInspectorSearchResults(
            searchText: text,
            listMode: listDisplayModel.listMode,
            displayMode: listDisplayModel.displayMode,
            focusId: searchModel.filterId
        )
    }

    /// Called exclusively by `loadChildrenViaSearch` when the user expands a `canOpen` item.
    ///
    /// **Two distinct paths — must not be confused with `results(text:)` which handles scoped views:**
    ///
    /// - `specialCategory` (folder / collection) → `inspectorSearchResults(listMode: .folder, focusId:)`
    ///   returns the folder's child items.
    /// - Regular item (PDF page, character, etc.) → `inspectorEntryResults(itemId:)` returns the
    ///   item's entries as flat direct results, ready to be stored as `FolderListItemModel.children`.
    ///
    /// **Why NOT `inspectorSearchResults` for regular items:**
    /// `inspectorScopedListResults` returns the focusId item itself (with `canOpen = true`), not its
    /// entries. That causes `loadChildrenViaSearch` to store the item as its own child → circular
    /// parent/child reference → infinite recursion in `flattenCachedChildren` → crash.
    public func results(text: String, focusId: UUID) async -> [SearchResult] {
        let isFolder = searchController.itemControllable.itemSync(for: focusId)?.specialCategory == true
        if isFolder {
            return await searchController.inspectorSearchResults(
                searchText: text,
                listMode: .folder,
                displayMode: listDisplayModel.displayMode,
                focusId: focusId
            )
        } else {
            // Returns entries as flat direct results — never the item itself.
            return searchController.inspectorEntryResults(
                searchText: text,
                itemId: focusId,
                displayMode: listDisplayModel.displayMode
            )
        }
    }

    /// Scoped view for `performDetailSearch`: always uses list mode so that per-module overrides
    /// (e.g. CharacterRPG's `focusedCharacterInspector`) receive the focus and return the
    /// item-as-root structure expected by the character inspector.
    /// The folder mode toggle in the inspector header does NOT apply here — the focused view
    /// always shows the focal item with its entries/children regardless of listMode.
    public func scopedResults(text: String, focusId: UUID) async -> [SearchResult] {
        await searchController.inspectorSearchResults(
            searchText: text,
            listMode: .list,
            displayMode: listDisplayModel.displayMode,
            focusId: focusId
        )
    }

    /// Sync expansion: folder/collection children OR item entries (inspector).
    /// Same logic as `results(text:, focusId:)` but purely synchronous via `itemSync`.
    @MainActor public func syncExpandResults(focusId: UUID) -> [SearchResult] {
        guard let item = searchController.itemControllable.itemSync(for: focusId) else { return [] }
        if item.specialCategory {
            let results = item.entries.compactMap { entry -> SearchResult? in
                guard let child = searchController.itemControllable.itemSync(for: entry.childId),
                      child.displayState == 0 else { return nil }
                let entryId = entry.id == entry.childId ? entry.id.childPath(of: item.id) : entry.id
                var result = SearchResult(
                    itemId: child.id, itemName: child.name,
                    module: searchController.itemControllable.config.module,
                    category: child.category,
                    entryId: entryId, entryName: nil, matchedContent: nil, relevanceScore: 0
                )
                result.canOpen = child.specialCategory
                return result
            }
            // Folders: alphabetical order. Collections: preserve entry order.
            if item.category == .folder {
                return results.sorted { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
            }
            return results
        } else {
            // Regular item: flat entry list (inspector entry expansion)
            return item.entries.map { entry in
                SearchResult(
                    itemId: item.id, itemName: item.name,
                    module: searchController.itemControllable.config.module,
                    category: item.category,
                    entryId: entry.id, entryName: entry.name,
                    matchedContent: entry.content.isEmpty ? nil : entry.content,
                    relevanceScore: 0
                )
            }.sorted { ($0.entryName ?? "").localizedCompare($1.entryName ?? "") == .orderedAscending }
        }
    }

    public func copy(listDisplayModel: ListDisplayModel) -> any SearchRootControllable {
        SearchLinkController(
            searchController: searchController,
            searchModel: searchModel.newSearchModel,
            listDisplayModel: listDisplayModel
        )
    }
}
