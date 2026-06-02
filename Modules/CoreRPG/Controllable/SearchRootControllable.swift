// @copyright André Trettin

import Foundation

public protocol SearchRootControllable: Sendable  {
    var searchModel: SearchModel { get }
    func results(text: String) async -> [SearchResult]
    /// Returns a new independent copy bound to `listDisplayModel` with its own `SearchModel`.
    /// Used by `FolderListController.copy(listModel:)` so detail controllers do not share
    /// the same search state as the parent list controller.
    @MainActor func copy(listDisplayModel: ListDisplayModel) -> any SearchRootControllable
}

extension SearchRootControllable {
    @MainActor func performSearch() async {
        // Cancel any ongoing search
        searchModel.cancelSearch()

//        guard !searchModel.searchText.isEmpty else {
//            searchModel.results = []
//            return
//        }

        let searchTask = Task { @MainActor in
            searchModel.isSearching = true
            defer { searchModel.isSearching = false }

            // Debounce only while the user is actively typing; skip the delay for
            // empty text so the initial list appears immediately on appear.
            if !searchModel.searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }

            searchModel.results = await results(text: searchModel.searchText)
        }

        searchModel.setSearchTask(searchTask)
        await searchModel.awaitCurrentSearch()
    }
}
