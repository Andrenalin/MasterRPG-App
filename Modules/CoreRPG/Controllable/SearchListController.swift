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

    public func results(text: String, focusId: UUID) async -> [SearchResult] {
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

    /// Called by `loadChildrenViaSearch` when the user toggles an item open.
    /// - Folders/collections: use `.folder` mode to return child items.
    /// - Regular items: use `inspectorEntryResults` to return entries as direct results.
    ///   (`.folder` mode returned nothing for non-folder items, breaking the toggle.)
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
            return await searchController.inspectorEntryResults(
                searchText: text,
                itemId: focusId,
                displayMode: listDisplayModel.displayMode
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
