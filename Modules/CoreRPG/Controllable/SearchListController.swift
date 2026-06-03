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
    let listDisplayModel: ListDisplayModel
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
    let listDisplayModel: ListDisplayModel
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
        let isFolder = await MainActor.run {
            searchController.itemControllable.itemSync(for: focusId)?.specialCategory == true
        }
        if isFolder {
            return await searchController.inspectorSearchResults(
                searchText: text,
                listMode: .folder,
                displayMode: listDisplayModel.displayMode,
                focusId: focusId
            )
        } else {
            // Returns entries as flat direct results — never the item itself.
            return await searchController.inspectorEntryResults(
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

    public func copy(listDisplayModel: ListDisplayModel) -> any SearchRootControllable {
        SearchLinkController(
            searchController: searchController,
            searchModel: searchModel.newSearchModel,
            listDisplayModel: listDisplayModel
        )
    }
}
