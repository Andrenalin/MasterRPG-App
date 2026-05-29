// @copyright André Trettin

import Foundation

@MainActor
public struct SearchListController {
    public init(searchController: any SearchControllable, searchModel: SearchModel) {
        self.searchController = searchController
        self.searchModel = searchModel
    }
    
    let searchController: any SearchControllable
    public let searchModel: SearchModel
}

extension SearchListController: SearchRootControllable {
    
    public func results(text: String) async -> [SearchResult] {
        await searchController.globalSearchResults(searchText: text)
    }
}
