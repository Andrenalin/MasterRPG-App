// @copyright André Trettin

import Foundation

public protocol SearchRootControllable: Sendable  {
    var searchModel: SearchModel { get }
    func results(text: String) async -> [SearchResult]
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

            // Small delay to debounce rapid typing
            try? await Task.sleep(for: .milliseconds(300))

            guard !Task.isCancelled else { return }

            searchModel.results = await results(text: searchModel.searchText)
        }

        searchModel.setSearchTask(searchTask)
        await searchModel.awaitCurrentSearch()
    }
}
