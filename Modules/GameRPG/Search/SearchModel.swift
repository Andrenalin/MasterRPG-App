// @copyright André Trettin

import CoreRPG
import Foundation

@MainActor
@Observable
final class SearchModel {
    init(searchText: String = "") {
        self.searchText = searchText
        self.results = [:]
        self.isSearching = false
    }

    var searchText: String
    var results: [NetworkModules: [SearchResult]] = [:]
    var isSearching = false
    var selection: SearchResult?

    var playerMode: Bool = false

    @ObservationIgnored private var _searchTask: Task<Void, Never>?

    func cancelSearch() {
        _searchTask?.cancel()
        _searchTask = nil
    }

    func setSearchTask(_ task: Task<Void, Never>) {
        _searchTask = task
    }

    func awaitCurrentSearch() async {
        await _searchTask?.value
    }

    deinit {
        _searchTask?.cancel()
    }
}
