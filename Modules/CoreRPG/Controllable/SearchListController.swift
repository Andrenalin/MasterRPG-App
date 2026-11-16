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
        let results = await searchController.listSearchResults(
            searchText: text,
            listMode: listDisplayModel.listMode,
            displayMode: listDisplayModel.displayMode,
            focusId: listDisplayModel.listMode == .folder ? searchModel.filterId : nil
        )
        return applyingSelectedTags(to: results, itemControllable: searchController.itemControllable)
    }

    /// Scoped view for `performDetailSearch`: folder mode to return the parent's children.
    public func scopedResults(text: String, focusId: UUID) async -> [SearchResult] {
        let results = await searchController.listSearchResults(
            searchText: text,
            listMode: .folder,
            displayMode: listDisplayModel.displayMode,
            focusId: focusId
        )
        return applyingSelectedTags(to: results, itemControllable: searchController.itemControllable)
    }

    /// Sync expansion: folder/collection children only (list search never expands item entries).
    @MainActor public func syncExpandResults(focusId: UUID) -> [SearchResult] {
        searchController.folderChildResults(focusId: focusId) ?? []
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
        let results = await searchController.inspectorSearchResults(
            searchText: text,
            listMode: listDisplayModel.listMode,
            displayMode: listDisplayModel.displayMode,
            focusId: searchModel.filterId
        )
        return applyingSelectedTags(to: results, itemControllable: searchController.itemControllable)
    }

    /// Scoped view for `performDetailSearch`: always uses list mode so that per-module overrides
    /// (e.g. CharacterRPG's `focusedCharacterInspector`) receive the focus and return the
    /// item-as-root structure expected by the character inspector.
    /// The folder mode toggle in the inspector header does NOT apply here — the focused view
    /// always shows the focal item with its entries/children regardless of listMode.
    public func scopedResults(text: String, focusId: UUID) async -> [SearchResult] {
        let results = await searchController.inspectorSearchResults(
            searchText: text,
            listMode: .list,
            displayMode: listDisplayModel.displayMode,
            focusId: focusId
        )
        return applyingSelectedTags(to: results, itemControllable: searchController.itemControllable)
    }

    /// Sync expansion: folder/collection children OR item entries (inspector).
    /// Same logic as `results(text:, focusId:)` but purely synchronous via `itemSync`.
    @MainActor public func syncExpandResults(focusId: UUID) -> [SearchResult] {
        if let children = searchController.folderChildResults(focusId: focusId) {
            return children
        }
        guard let item = searchController.itemControllable.itemSync(for: focusId) else { return [] }
        // Regular item: flat entry list (inspector entry expansion).
        // No search active here (empty-search rebuild) — preserve the item's own
        // entry order (e.g. table rows), same as a collection's children.
        return item.entries.map { entry in
            SearchResult(
                itemId: item.id, itemName: item.name,
                module: searchController.itemControllable.config.module,
                category: item.category,
                entryId: entry.id, entryName: entry.name,
                matchedContent: entry.content.isEmpty ? nil : entry.content,
                relevanceScore: 0
            )
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

extension SearchControllable {
    /// The visible children of a folder or collection as search results, `nil` when `focusId` is
    /// not a folder or collection. Folders sort alphabetically, collections keep their entry order.
    /// Shared by `SearchListController` and `SearchLinkController`. See CODE_AUDIT_26 §9.8.
    @MainActor func folderChildResults(focusId: UUID) -> [SearchResult]? {
        guard let item = itemControllable.itemSync(for: focusId), item.specialCategory else { return nil }
        let results = zip(item.entries, item.memberRowIds()).compactMap { entry, entryId -> SearchResult? in
            guard let child = itemControllable.itemSync(for: entry.childId),
                  child.displayState == DisplayStateMask.fullVisible.rawValue else { return nil }
            var result = SearchResult(
                itemId: child.id, itemName: child.name,
                module: itemControllable.config.module,
                category: child.category,
                entryId: entryId, entryName: nil, matchedContent: nil, relevanceScore: 0
            )
            result.canOpen = child.specialCategory  // nested folders can themselves be expanded
            return result
        }
        if item.category == .folder {
            return results.sorted { $0.itemName.localizedCompare($1.itemName) == .orderedAscending }
        }
        return results
    }
}
