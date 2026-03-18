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
    
    var searchTask: Task<Void, Never>?
}
